---
layout: post
title: 云原生MySQL初探之一
---

云原生概念近些年越来越火热与普及，但是在MySQL领域似乎一直没有太大的动静。貌似DBA们都岁月静好的坚守传统的方式。我认为主要原因两点：

  1. MySQL基本都保存着业务的核心数据，不会轻易变动
  2. MySQL是重状态的业务，而云原生的基石kubernetes本身是为了无状态业务设计，对于有状态业务的管理并不是长处

线上业务稳定压倒一切，对于第一点无可厚非。而第二点，随着kubernetes 更新到1.20大版本，对于PV PVC StatefulSet的支持都有长足的进步。所以是时候尝试一下将MySQL变成云原生应用了。

## 构想

初步的期望是尽可能通过与kubernetes交互就可以实现MySQL的管理，具体需求如下：
  
  - 以kubernetes的方式创建MySQL主从 将一个MySQL主从架构称为一个MySQL Cluster
  - MySQL 中的schema（database） 也被k8s管理
  - 用户权限管理
  - 备份管理

以上四个基本需求明显仅靠k8s自身的controller无法实现，所以需要多个CRD来描述MySQL cluster, user, database, backup.也需要实现一个mysql-operator来实现这些CRD的管理

那么k8s能提供什么？

`StatfulSet` STS能够保证MySQL master节点与所有的slave节点直接配置的完全一致。同时STS支持的PVC template通过volume的亲缘性调度到合适的node上

PV PVC StorageClass 为每一块高性能硬盘创建一个PV，通过PVC挂载给一个MySQL实例使用并且将所有的PV声明为同一个StorageClass便于STS的调度

`Service` 每个MySQL使用三个service，master service始终指向 master节点，replicas service指向所有的slave节点，一个以cluster name命名的service指向所有的节点，为了生成 sts的 pod-name.svc.namespace的内部域名。业务使用master或replicas名称来访问MySQL实例

有以上的想法先不急着开工做，Google一下看看有没有前人做过类似的事情。Google可以查到两个项目

  - [mysql-operator](https://github.com/oracle/mysql-operator) Oracle 开发，但是3年前已经不更新了
  - [mysql-operator](https://github.com/presslabs/mysql-operator) 由WorldPress的presslabs 开发，目的是满足WorldPress的部署

presslabs 开发的operator 看文档是完全满足需求，那么直接使用尝试一下。

## 测试

### 测试环境

使用腾讯云 TKE 部署一个独立 k8s集群，三节点master，两个worker使用 高IO型IT5 具备本地NVME SSD用来部署MySQL，一个worker使用标准型S1，用来运行operator，sysbench

```bash
NAME           STATUS   ROLES    AGE   VERSION         INSTANCE-TYPE
10.0.190.131   Ready    master   29h   v1.18.4-tke.6   S1.LARGE4
10.0.190.143   Ready    master   29h   v1.18.4-tke.6   S1.LARGE4
10.0.190.200   Ready    <none>   29h   v1.18.4-tke.6   IT5.4XLARGE64
10.0.190.223   Ready    master   29h   v1.18.4-tke.6   S1.LARGE4
10.0.190.239   Ready    <none>   29h   v1.18.4-tke.6   S1.LARGE8
10.0.190.36    Ready    <none>   29h   v1.18.4-tke.6   IT5.4XLARGE64
```

### 部署 operator

[mysql-operator](https://github.com/presslabs/mysql-operator) 本身提供helm charts，可以直接通过helm安装，具体项目文档中有这里不再赘述。但是测试环境是一个网络隔离环境，无法访问外网，这里下载 chart包之后执行

```bash
➜  mysql-operator ls
Chart.yaml  crds  README.md  templates  values.yaml
➜  mysql-operator helm template --release-name "mysql" . > ../mysql-operator.yaml
WARNING: Kubernetes configuration file is group-readable. This is insecure. Location: /home/harrison/.kube/config
WARNING: Kubernetes configuration file is world-readable. This is insecure. Location: /home/harrison/.kube/config
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
manifest_sorter.go:192: info: skipping unknown hook: "crd-install"
➜  mysql-operator
```
通过helm 命令本地渲染出yaml文件使用

``` bash
➜  mysql-operator kubeclt apply -f ./crds/ 
➜  mysql-operator kubectl apply -f mysql-operator.yaml 
➜  mysql-operator kubectl get pod
NAME                     READY   STATUS    RESTARTS   AGE
mysql-mysql-operator-0   2/2     Running   0          23h
```
以上两步，添加crd然后添加operator的相关资源之后，mysql-operator便启动了

在此之后可以通过以下命令具体查看每种资源的定义

```
kubectl explain MysqlCluster
kubectl explain MysqlUser
kubectl explain MysqlDatabase
kubectl explain MysqlBackup
```

### 部署 MySQL 集群

1. node处理
  10.0.190.200，10.0.190.36 两个node上的本地ssd需要首先分区格式化挂载到统一挂载点比如 `/mnt/disk/ssd0`

2. PV创建

``` yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: "example-local-pv"
spec:
  capacity:
    storage: 3000Gi
  accessModes:
  - "ReadWriteOnce"
  persistentVolumeReclaimPolicy: "Retain"
  storageClassName: "local-ssd"
  local:
    path: "/mnt/disk/ssd0"
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: "kubernetes.io/hostname"
          operator: "In"
          values:
          - "10.0.190.200"
```
修改name 与 IP为每个node上的ssd分别创建一个pv

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: "local-ssd"
provisioner: "kubernetes.io/no-provisioner"
volumeBindingMode: "WaitForFirstConsumer" ## 一旦一个PVC与之绑定之后禁止再次绑定别的PVC，防止mysql实例的数据发生变化
reclaimPolicy: "Retain"
```
同时创建如上的StorageClass，为了创建的每个副本可以通过StorageClass动态的获取属于自己的PV

3. MySQL 集群创建

YAML如下

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
data:
  # root password is required to be specified
  ROOT_PASSWORD: YWJjQkNBMTIz # 改成你的base64之后的密码
  ## application credentials that will be created at cluster bootstrap
  # DATABASE:
  # USER:
  # PASSWORD:

---
apiVersion: mysql.presslabs.org/v1alpha1
kind: MysqlCluster
metadata:
  name: my-cluster
spec:
  replicas: 2
  secretName: my-secret
  image: percona:5.7
  mysqlConf:  ## 设置my.cnf不要修改ib file path 由于PVC挂载的路径是写死在/var/lib/mysql的默认路径
   innodb-buffer-pool-size: 48G
   innodb-buffer-pool-instances: 8
   innodb-data-file-path: ibdata1:1024M:autoextend
   innodb-flush-log-at-trx-commit: 1
   innodb-log-buffer-size: 32M
   innodb-log-file-size: 1024M
   innodb-log-files-in-group: 5
   innodb-max-dirty-pages-pct: 50
   innodb-file-per-table: 1
   innodb-status-file: 1
   innodb-io-capacity: 10000
   transaction-isolation: READ-COMMITTED
   innodb-flush-method: O_DIRECT
   innodb-thread-concurrency: 0
   innodb-read-io-threads: 8
   innodb-write-io-threads: 8   
   innodb-print-all-deadlocks: "on"
   innodb-deadlock-detect: "on" 
   innodb-lock-wait-timeout: 30
  volumeSpec: ## PVC 挂载在容器的/var/lib/mysql
    persistentVolumeClaim:
      storageClassName: local-ssd  # 这里使用 storageclussname 来关联pv
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1000Gi
```

以上启动mysql会与到如下的报错

```
kubectl logs my-cluster-mysql-0 init

Create Google Drive service-account.json file.
Create rclone.conf file.
2021-03-08T12:33:34.641Z	INFO	sidecar	environment is not set	{"key": "MY_SERVER_ID_OFFSET"}
2021-03-08T12:33:34.641Z	INFO	sidecar	environment is not set	{"key": "INIT_BUCKET_URI"}
2021-03-08T12:33:34.641Z	INFO	sidecar	environment is not set	{"key": "BACKUP_COMPRESS_COMMAND"}
2021-03-08T12:33:34.641Z	INFO	sidecar	environment is not set	{"key": "BACKUP_DECOMPRESS_COMMAND"}
2021-03-08T12:33:34.641Z	INFO	sidecar	environment is not set	{"key": "RCLONE_EXTRA_ARGS"}
2021-03-08T12:33:34.641Z	INFO	sidecar	environment is not set	{"key": "XBSTREAM_EXTRA_ARGS"}
2021-03-08T12:33:34.641Z	INFO	sidecar	environment is not set	{"key": "XTRABACKUP_EXTRA_ARGS"}
2021-03-08T12:33:34.641Z	INFO	sidecar	environment is not set	{"key": "XTRABACKUP_PREPARE_EXTRA_ARGS"}
2021-03-08T12:33:34.641Z	INFO	sidecar	environment is not set	{"key": "XTRABACKUP_TARGET_DIR"}
2021-03-08T12:33:34.641Z	INFO	sidecar	environment is not set	{"key": "INITFILE_EXTRA_SQL"}
2021-03-08T12:33:34.641Z	INFO	sidecar	cloning command	{"host": "my-cluster-mysql-0"}
2021-03-08T12:33:35.668Z	INFO	sidecar	service was not available	{"service": "my-cluster-mysql-replicas", "error": "Get \"http://my-cluster-mysql-replicas:8080/health\": dial tcp 192.168.253.99:8080: connect: connection refused"}
2021-03-08T12:33:36.692Z	INFO	sidecar	service was not available	{"service": "my-cluster-mysql-master", "error": "Get \"http://my-cluster-mysql-master:8080/health\": dial tcp 192.168.253.26:8080: connect: connection refused"}
2021-03-08T12:33:36.692Z	INFO	sidecar	nothing to clone from: empty cluster initializing
2021-03-08T12:33:36.692Z	INFO	sidecar	configuring server	{"host": "my-cluster-mysql-0"}
2021-03-08T12:33:36.692Z	INFO	sidecar	error while reading PURGE GTID from xtrabackup_binlog_info
```

以上报错是由于init container尝试从 `xtrabackup_binlog_info` 中获取上次备份的GTID用来做增量备份，但是MySQL第一次启动从来没有过备份这里做了多余的检查，修改代码`pkg/sidcar/util.go`的`readPurgedGTID`函数如下

``` golang
// readPurgedGTID returns the GTID from xtrabackup_binlog_info file
func readPurgedGTID() (string, error) {
	file, err := os.Open(fmt.Sprintf("%s/xtrabackup_binlog_info", dataDir))
	if err != nil && !os.IsNotExist(err) {
		return "", err
	}

	if os.IsNotExist(err) {
		return "", nil
	}

	defer func() {
		if err1 := file.Close(); err1 != nil {
			log.Error(err1, "failed to close file")
		}
	}()

	return getGTIDFrom(file)
}
```

重新编译制作image之后重新部署operator，目前以上问题已经给他们提了issue，等对方合并pr之后便可使用官方image，我的个人修改版为

```
harrisonzhu/mysql-operator-orchestrator:v0.5.0-rc.2
```

PS. 此修改版除了修改以上问题之外，同时支持备份文件存储到腾讯云OSS

经过以上折腾之后

```
kubectl get mysqlclusters                     
NAME         READY   REPLICAS   AGE
my-cluster   True    2          23h

kubectl get sts        
NAME                   READY   AGE
my-cluster-mysql       2/2     23h


kubectl get pod                                            
NAME                     READY   STATUS    RESTARTS   AGE
my-cluster-mysql-0       4/4     Running   1          9h
my-cluster-mysql-1       4/4     Running   0          23h
mysql-mysql-operator-0   2/2     Running   0          24h

kubeclt get svc
NAME                         TYPE        CLUSTER-IP        EXTERNAL-IP   PORT(S)             AGE
my-cluster-mysql             ClusterIP   192.168.254.89    <none>        3306/TCP            23h  # 绑定在两个pod上
my-cluster-mysql-master      ClusterIP   192.168.255.147   <none>        3306/TCP,8080/TCP   23h  # 始终绑定在master POD
my-cluster-mysql-replicas    ClusterIP   192.168.252.162   <none>        3306/TCP,8080/TCP   23h  # 绑定在所有的slave 上

```

集群中 创建了一个 MySQL集群，operator翻译出了一个对应的 2 副本的sts，启动了两个mysql，再检查一下pvc，pv的情况

```
kubectl get pvc          
NAME                          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data-my-cluster-mysql-0       Bound    example-local-pv                           3000Gi     RWO            local-ssd      23h
data-my-cluster-mysql-1       Bound    example-local-pv-1                         3000Gi     RWO            local-ssd      23h

kubectl get pv 
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                 STORAGECLASS   REASON   AGE
example-local-pv                           3000Gi     RWO            Retain           Bound    default/data-my-cluster-mysql-0       local-ssd               23h
example-local-pv-1                         3000Gi     RWO            Retain           Bound    default/data-my-cluster-mysql-1       local-ssd               23h
```

两个PVC分别绑定了两台机器上的PV

再详细看一下两个Pod的状态，由于过长这里只展示 Labels信息

```
kubectl describe pod my-cluster-mysql-0 
Name:         my-cluster-mysql-0
Namespace:    default
Priority:     0
Node:         10.0.190.200/10.0.190.200
Start Time:   Tue, 09 Mar 2021 11:38:44 +0800
Labels:       app.kubernetes.io/component=database
              app.kubernetes.io/instance=my-cluster
              app.kubernetes.io/managed-by=mysql.presslabs.org
              app.kubernetes.io/name=mysql
              app.kubernetes.io/version=5.7.31
              controller-revision-hash=my-cluster-mysql-68b4975b48
              healthy=yes
              mysql.presslabs.org/cluster=my-cluster
              role=replica
              statefulset.kubernetes.io/pod-name=my-cluster-mysql-0

kubectl describe pod my-cluster-mysql-1
Name:         my-cluster-mysql-1
Namespace:    default
Priority:     0
Node:         10.0.190.36/10.0.190.36
Start Time:   Mon, 08 Mar 2021 21:54:23 +0800
Labels:       app.kubernetes.io/component=database
              app.kubernetes.io/instance=my-cluster
              app.kubernetes.io/managed-by=mysql.presslabs.org
              app.kubernetes.io/name=mysql
              app.kubernetes.io/version=5.7.31
              controller-revision-hash=my-cluster-mysql-68b4975b48
              healthy=yes
              mysql.presslabs.org/cluster=my-cluster
              role=master
              statefulset.kubernetes.io/pod-name=my-cluster-mysql-1

```
可以看到0号 pod目前 `role=replica` 也就代表这里 0号POD中的mysql目前处于slave的状态，而1号 pod处于 master的状态。一般第一个启动的pod也就是0号会成为master，这里因为手动delete过0号pod测试主从切换，以及带数据启动的情况。便成为了现在的情况。

可以通过kubectl exec或者建立一个用于测试的pod 通过service name 进入对应的pod检查mysql的具体状态，这里不再列出，继续测试其它功能

4. databae，user的创建管理

``` yaml
apiVersion: mysql.presslabs.org/v1alpha1
kind: MysqlDatabase
metadata:
  name: my-database
spec:
  database: sbtest
  clusterRef:
    name: my-cluster
    namespace: default
```

``` yaml
apiVersion: v1
kind: Secret
metadata:
  name: sbtest-password
data:
  PASSWORD: MTIzYWJjQUJD
---
apiVersion: mysql.presslabs.org/v1alpha1
kind: MysqlUser
metadata:
  name: sbtest-user
spec:
  user: sbtest
  clusterRef:
    name: my-cluster
    namespace: default
  password:
    name: sbtest-password
    key: PASSWORD
  allowedHosts:
    - "%"
  permissions:
    - schema: sbtest
      tables: ["*"]
      permissions:
        - "ALL PRIVILEGES"

```

以上便很方便的创建了一个`sbtest` database，并且创建一个`sbtest` user 赋予 sbtest库的全部权限