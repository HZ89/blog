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

This section describes how the group is created and how the initial members securely establish the shared encryption key (`K0`).

1. **Admin generates the initial group key (`K0`)**:
   ```
   K0 = Random(32 bytes)
   ```
2. **Admin encrypts `K0` for each initial member using their public keys**:
   ```
   EncK0_M = Encrypt(K0, PubKey_M)
   ```
3. **The server stores encrypted keys (`EncK0_M`) but cannot decrypt them.**
4. **Each member retrieves and decrypts `K0`**:
   ```
   K0 = Decrypt(EncK0_M, PrivateKey_M)
   ```

### **4.2 New Member Integration**

When a new member is added, the admin verifies their public key. The admin also provides its own public key to the new member over a P2P channel, while the new member may independently fetch the admin’s key from an OpenPGP key server. Once keys are verified, the group key (`K0`) is shared, and the new member can access encrypted history.

#### **Step 1: New Member Requests to Join**

1. **New member generates a key pair** and submits `PubKey_X` to the admin.
2. **Admin verifies and signs `PubKey_X**:
   ```
   Signed_PubKey_X = Sign(PubKey_X, PrivateKey_Admin)
   ```
3. **Server broadcasts `PubKey_X` and `Signed_PubKey_X` to all members.**
4. **Existing members verify `Signed_PubKey_X`**:
   ```
   Verify(Signed_PubKey_X, PubKey_Admin)
   ```

#### **Step 2: Admin Shares Its Public Key With the New Member**

1. **Admin initiates a P2P communication** to send the admin’s public key (`PubKey_Admin`) directly to the new member.
2. **Simultaneously**, the new member **attempts to fetch `PubKey_Admin`** from an **OpenPGP key server** (or any external key directory).
3. **If both sources match**, the new member gains high confidence in `PubKey_Admin`.
4. **If only one source is available**, the new member trusts that source by default.

#### **Step 3: Encrypting and Sharing the Group Key (`K0`)**

1. **An existing member encrypts `K0` for `X`**:
   ```
   EncK0_X = Encrypt(K0, PubKey_X)
   ```
2. **New member retrieves and decrypts `K0`**:
   ```
   K0 = Decrypt(EncK0_X, PrivateKey_X)
   ```

#### **Step 4: Providing Encrypted History Messages**

1. **Server stores recent encrypted messages (`EncMsg`) and serves them to new members.**
2. **New member retrieves and decrypts stored messages using `K0`**:
   ```
   History = [EncMsg_1, EncMsg_2, ..., EncMsg_N]
   Decrypted_History = [Decrypt(EncMsg_1, K0), ..., Decrypt(EncMsg_N, K0)]
   ```

✅ **Ensures new members can access previous conversations securely.**  
✅ **Prevents the server from accessing message contents.**  
✅ **New members integrate into the group without missing prior context.**  

### **4.3 Message Sending Process**  

When a member sends a message to the group, it follows a secure process to ensure **end-to-end encryption (E2EE), integrity, and authenticity**.

1. **Sender composes message (`M`) and generates a unique 128-bit message ID (`Msg_ID`).**
2. **Encrypt the message using `Kn` (current shared key):**
   ```
   CipherText = Encrypt(M, Kn)
   ```
3. **Sign the encrypted message:**
   ```
   Signature = Sign(CipherText || Msg_ID, PrivateKey_Sender)
   ```
4. **Broadcast the encrypted message to all members.**
5. **Each recipient verifies the signature and checks for out-of-order or duplicate messages:**
   - If `Msg_ID` is already processed, the message is ignored.
   - If a message arrives out of order, it is temporarily buffered for reordering.
6. **If valid, decrypt `CipherText` using `Kn`**:
   ```
   M = Decrypt(CipherText, Kn)
   ```

✅ **Ensures message authenticity and integrity.**  
✅ **Prevents replay attacks and message duplication.**  
✅ **Allows recipients to handle out-of-order messages efficiently.**  

### **4.4 Key Rotation & Historical Decryption**

To maintain ongoing security, the group key (`K0`) must be periodically updated. Each updated key (`K1`, `K2`, etc.) should still be able to decrypt older messages, ensuring new members can view history.

1. **Periodic or Event-Based Key Rotation**
   - After a set duration (e.g., daily) or a certain number of messages, the group derives a new key:
     ```
     Kn = HMAC(K(n−1), "rotation")
     ```
   - This approach ensures forward secrecy while still allowing new key holders to decrypt prior content.
2. **Sharing the New Key**
   - An existing member encrypts `Kn` for each current member's public key.
   - If a new member joins after the rotation, they are given `Kn` directly.
3. **Decrypting Historical Messages**
   - All older messages remain decryptable by `Kn` because either:
     - The same encryption key is reused across periods (less secure), or
     - Each key can derive previous keys in a ratchet-like manner (more secure):
       ```
       K(n−1) = HMAC(Kn, "reverse")
       ```
   - Members who join late can request older messages from the server and decrypt them using the rotated key chain.

### **4.5 Preventing Ghost Users**

SGMP ensures that **only authorized members participate in the group** and prevents unauthorized additions (Ghost Users).

#### **Member-Driven Key Distribution**

- **Only existing members encrypt `K0` for new members.**
- The server **cannot insert unauthorized members** because it does not control `K0`.

#### **Merkle Tree Membership Verification**

- Each member maintains a **Merkle Tree hash** of the group’s public keys.
- The **Merkle Root (`H_root`) is signed by all members**:
   ```
   SignedH_root = Sign(H_root, PrivateKey_M)
   ```
- Before encrypting a message, members **verify `H_root` to ensure group integrity**.

#### **Distributed Key Approval**

- A **new member must receive `K0` from multiple existing members**, preventing a single compromised entity from approving unauthorized users.

✅ **Ghost users cannot decrypt messages because they never receive `K0`.**  
✅ **Server cannot manipulate membership without being detected.**  

## **5. Summary of Key Functions Summary of Key Functions**

| Scenario | Responsible for Encrypting `K0`? |
|----------------|------------------------------|
| **Group creation** | ✅ Admin encrypts `K0` for all initial members. |
| **New member joins** | ✅ Any existing member encrypts `K0` for them. |
| **Preventing ghost users** | ✅ Only real members encrypt and share `K0`. |

✅ **Decentralized key exchange prevents unauthorized access.**  
✅ **New members access history securely while preventing exposure.**  
✅ **Server cannot interfere with group security.**
