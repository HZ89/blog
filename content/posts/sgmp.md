+++
title = "Secure Group Messaging Protocol (SGMP)"
date = "2025-02-03T21:35:11+08:00"
#dateFormat = "2006-01-02" # This value can be configured for per-post date formatting
author = "Harrison Zhu"
authorTwitter = "" #do not include @
cover = ""
tags = ["E2EE", "P2P"]
keywords = ["Secure Messaging", "Ghost User Prevention", "Forward Secrecy"]
description = "SGMP is a cryptographic protocol designed for secure group messaging with end-to-end encryption, decentralized key management, and protection against ghost user attacks. It enables efficient peer-to-peer message exchange and periodic key rotation while preventing unauthorized access."
showFullContent = false
readingTime = false
hideComments = false
+++

## **1. Introduction**
Secure Group Messaging Protocol (**SGMP**) is a cryptographic protocol for **end-to-end encrypted (E2EE) group communication**. Unlike traditional models, SGMP eliminates server trust by ensuring **members independently maintain group state and exchange encryption keys**, preventing unauthorized member insertion (**Ghost User Attacks**).

## **2. Key Features**

✅ **Decentralized Key Management**: Members maintain group state and exchange keys.
✅ **Shared Key with Periodic Rotation**: Messages are encrypted using a shared symmetric key updated regularly.
✅ **Server-Assisted Encrypted Key Storage**: The server only stores encrypted keys.
✅ **New Members Can Access History**: Members securely share past encrypted messages with new members.
✅ **No Trust in Server for Group Membership**: Members validate all member lists, preventing ghost users.

## **3. Cryptographic Primitives**

| Component | Algorithm |
|------------|----------------|
| **Asymmetric Key Exchange** | X3DH (Signal Protocol) |
| **Symmetric Encryption** | AES-GCM or ChaCha20-Poly1305 |
| **Key Derivation** | HMAC-SHA256 |
| **Group Membership Verification** | Merkle Tree Hashing |
| **Message Signing** | Ed25519 |

## **4. Protocol Overview**

### **4.1 Group Initialization**

- The **admin** generates an initial **shared group key (K0)** and distributes it securely.
- The **server stores only encrypted keys** `{EncK0_M}` for each member, ensuring it cannot decrypt messages.

### **4.2 Message Transmission**

- Messages are encrypted with the **current shared key (Kn)**.
- Messages are sent **directly between members (P2P)**.
- The server **does not relay messages**.

### **4.3 Key Rotation & History Decryption**

- The group periodically **updates the shared key**:
  
  ```
  Kn = HMAC(Kn-1, "next")
  ```

- **Older messages remain decryptable**, ensuring historical access for new members.

### **4.4 New Member Integration**

- Existing members validate the new member and **securely share the group key**.
- The server **cannot insert members or generate keys**.

### **4.5 Preventing Ghost Users**

#### **Defense Mechanism 1: Member-Driven Key Distribution**

- **Only existing members encrypt K0 for new members.**
- If the server **adds a fake user X'**, no one will encrypt `K0` for them.

#### **Defense Mechanism 2: Merkle Tree Membership Verification**

- Each member maintains a **Merkle Tree hash** of the current **group members list**.
- The **root hash (`H_root`) is signed by all members** and shared periodically.
- Before encrypting a message, a sender **validates the Merkle Tree hash** against their locally stored version to detect unauthorized changes.

#### **How it Works**

1. Each member maintains a **Merkle Tree** where:
   - **Leaf nodes** = Public keys of all members.
   - **Internal nodes** = Hashes of concatenated child nodes.
   - **Root node (`H_root`)** = The final hash that represents the full group state.
   
   ```
             H_root
             /    \
         H1        H2
        /  \      /  \
      A    B    C    D
   ```

2. The Merkle root (`H_root`) is signed by all members and **stored in the group metadata**:
   
   ```
   SignedH_root = Sign(H_root, PrivateKey_M)
   ```

3. Before encrypting a message, a sender:
   - Requests the latest **Merkle root hash** from peers.
   - Compares it with their stored **H_root**.
   - If **mismatches** are detected, **the sender halts communication** and alerts the group.

✅ **Ghost users cannot be inserted because every member cross-verifies the Merkle root.**  
✅ **If the server alters the member list, the hash changes and everyone detects it.**  
✅ **Any malicious changes will cause signature mismatches, preventing undetected tampering.**

#### **Defense Mechanism 3: Distributed Key Approval**

- A **new member must receive encrypted K0 from multiple existing members**.
- This **prevents a single compromised member from approving ghost users**.
- **Only real members encrypt and share keys.**
- **Server cannot generate encrypted keys (`EncK0_X'`).**
- **Merkle Tree verification prevents unauthorized modifications.**

## **5. Summary of Key Functions**

| Scenario | Responsible for Encrypting `K0`? |
|----------------|------------------------------|
| **Group creation** | ✅ Admin encrypts `K0` for all initial members. |
| **New member joins** | ✅ Any existing member encrypts `K0` for them. |
| **Preventing ghost users** | ✅ Only real members encrypt and share `K0`. |

✅ **Decentralized key exchange prevents unauthorized access.**  
✅ **New members access history securely while preventing exposure.**  
✅ **Server cannot interfere with group security.**
