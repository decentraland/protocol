# Decentraland Protocol for Explorers

## Introduction

### What is Decentraland?

Decentraland is an open platform to socialize based on Web3 and public key cryptography. The users of the platform own the assets and both the governance process and the decisions made through it. Many different products can be considered part of Decentraland, including but not limited to a 3D explorer of the world created by the users and its rendering, content, replication and communication layers. This document focuses on a particular use case and subset of Decentraland, its _Explorer_ and the protocols required to make it work.

### What to expect from this document?

This document serves as reference to outline the boundaries of what the Decentraland protocol for Explorers _is_. It defines the common mechanisms and protocols (sometimes including its messages and serializations) to make that information available to implementers willing to create their own versions of the Explorer.

## Layers of the Explorer protocol

To describe the Explorer protocol, the layers described in the [Decentraland Whitepaper (2017)](whitepaper) will be quoted. The initial layers were the first three, this document will also introduce a forth layer: Runtime layer

1. **Consensus layer**: Track land ownership and its content.
2. **Content layer**: Download assets using a decentralized distribution system.
3. **Real-time layer**: Enable users’ world viewers to connect to each other.
4. **Runtime layer**: Execute experiences the explorer.

### Consensus layer

Decentraland uses smart contracts to maintain a ledger of ownership of each of the (ownable) assets for the Explorer. The original whitepaper was scoped only to the LAND contract, that scope increased with the passing of time and the addition of new asset types like Wearables and Emotes, Names and Estates.

#### LAND

The [LAND contract](land-contract) establishes the ownership in the Ethereum network of parcels of land, those are non-fungible tokens that map 1-to-1 with the Decentraland Map, each token encodes a signed `(x,y)` position in the map. We call the map of the LAND contract "Genesis City". The whitepaper established that each plot of LAND corresponds to 10x10 meters of virtual land. This was changed to 16x16 meters [using the first governance app](https://agora.decentraland.org/polls/5fa066aa-bbd7-42bd-a8e6-a6c2c1965801).

![Genesis City][genesis-city]

#### Names

Names are a crucial part of the Identity, to prevent impersonation and to continue leveraging smart contracts, Decentraland uses tokenized names using an Ethereum Name Service (ENS) subdomain `.dcl.eth`. These names are ERC-721 tokens, that makes them owneable and transferrable, and they live in Ethereum Mainnet.

#### Wearables

Wearables are built on top of a variety of smart contracts deployed both to Ethereum (Mainnet) and Polygon. The first era of wearables still live in Ethereum, we call them L1. Those were convenient but expensive to operate. To supass this limitation a new technology was developed "L2 Collections".

_Collections_ are a set of smart contracts deployed to Polygon (or other EVM compatible networks) to create, manage and own a list of Items.

_Items_ are ERC-721 compatible tokens. Those can be limited in supply and share a common representation. The representation is the same for each item of the same kind, and it is used to locate the content of the item for applications like the Explorer or the Marketplace.

Collections are generic smart contracts that are designed to fulfill a wide variety of use cases. Starting with wearables, collections were configured to depend on a Wearables committee to approve/reject the content (representation) of each item. This process is governed by the [Decentraland DAO][dao]. That means that the community decides from the publication and secondary sales fees to the [group of people](https://governance.decentraland.org/transparency/) that curates the content of the wearables. The curation process happens in the [Builder][] tool and it is connected to the [forum](https://forum.decentraland.org/c/community-wearables/12).

#### DAO

Historically, there was many implementations of governance apps for Decentraland. Starting with [Agora][] (off-chain signatures), then Aragon and lastly a [snapshot-based](https://snapshot.org/#/snapshot.dcl.eth). Nowadays, the governance process happens entirely in the [Governance App][dao] and on-chain proposals are enacted using Aragon by the [DAO Committee](https://governance.decentraland.org/transparency). Their principal responsibility is to enact binding proposals on-chain like listing Point of Interests, sending Grants, and any other operations involving the DAO's smart contracts.

### Content layer

The Decentraland Explorer and other applications render representations of the assets from the consensus layer. The content layer defines the mechanisms in which the content is:

1. **Signed**, **validated** and **uploaded** to a node
2. **Replicated** to other nodes and
3. **Served** to the final users

To do so, a [content-server](https://github.com/decentraland/catalyst) was created. It is a service that runs inside a Catalyst.

> A _catalyst node_ is a bundle of services that self-contain a copy of Decentraland. The DAO [governs a curated list of trusted catalysts](https://governance.decentraland.org/?type=catalyst) that hold a working copy of Decentraland. It contains everything necessary to make the Explorer work.

The content server stores and synchronizes _Entities_.

An [Entity](https://github.com/decentraland/common-schemas/blob/be7213b40a2180a9a99035eb87e8a5d4b8438e7f/src/platform/entity.ts#L21-L37) is a signed data structure holding a list of content files, a deployment date and pointers. A pointer is a human readable "shortcut" to the entity i.e. the [`0,0`](https://peer.decentraland.org/content/entities/scenes?pointer=0,0) representation of a LAND. Every time an entity is deployed and accepted by the network, the pointers for that entity will now point to the newest entity for that set of pointers. That is the mechanism used to change the content of the land, wearables and emotes.

Unlike LAND, wearables and emotes have [URN pointers](https://github.com/decentraland/urn-resolver/blob/b11aeb677e06e1a9e1d7994efa98a5f11867f854/test/urn.spec.ts#L138-L147). URN are used to reference any asset inside Decentraland, the technology was selected in pursue of a common identifier that enables [extensibility to other networks or remote assets](https://github.com/decentraland/urn-resolver/blob/b11aeb677e06e1a9e1d7994efa98a5f11867f854/test/urn.spec.ts#L269-L280) and [interoperability](https://github.com/common-metaverse/urn-namespaces) with other platforms.

> TODO: Describe entities format

> TODO: Describe entities content restrictions

> TODO: Describe entities IPFS CIDs

> TODO: Describe AuthChain

#### Endpoints that are part of the protocol

##### `GET /contents/:cid` Download an entity or content file

Used to download the content. This endpoint is used by the content-server synchronization and by the explorer.

##### `POST /entity` Upload a new entity

The `POST /entity` must run validations to either accept or reject an entity. Depending on its type and querying the Consensus layer.

This endpoint is used by the tooling to upload content.

##### `POST /entities/active` Query active entities

Used to discover the map around the user. This endpoint is used by the explorer.

##### TODO: Get and Deploy profiles

#### Identity Storage

> TODO: Persistence layer for profiles, separate Profile from Avatar.
> TODO: Validations of the served content (lambdas) to check ownership

### Interactive layer

#### Chat
To have a complete social experience Explorers need to support some kind of chat among users. There will be three types of chats, private dms, channels and global. 

Global chat (as in chatting with people around in world) will be supported by the comms service, leveraging the p2p protocol which connects people within a single island (or whatever virtual network available). Everyone is allowed to talk in the global chat, even guests.

The [Matrix protocol](https://matrix.org/) will be leveraged for private and channel support, explorers should connect to a Matrix [homeserver](https://matrix.org/faq/#can-i-write-a-matrix-homeserver%3F) and all interactions will be saved in a single Matrix instance (as expected by the protocol), data will not be shared amongst Matrix instances. So, if a given explorer is connected to a Matrix instance, when switching homeservers, the data will not be synchronized between instances. 

On the homeserver side the main responsibility, besides implementing the Matrix protocol, is to support authentication via an AuthChain. This will enable login using a wallet, allowing explorers to use different devices maintaining the same information. Since a wallet is used for login, users will be required to own one for chatting with other users via this method.

> TODO: Write about comms

> TODO: Write about messages to share profiles via comms

### Runtime layer

Decentraland Explorers are often compared with operative systems that run programs, those are the scenes. Each scene in Decentraland is bound to a program that runs in a sandboxed environment. A set of functions is exposed to this sandboxed environment to enable the scene to communicate with the Rendering engine.

_The Rendering Engine_ is a component of the explorer that is in charge of interpreting messages of scenes and convert those bits of information into a 3D representation of the scene. It is also in charge of managing the load/unload of resources and of forwarding input and player information back to the scenes for interactivity.

> TODO: Write about the lifecycle of a scene and how it is loaded

> TODO: Write about the ECS6 and the legacy protocol

> TODO: Write about the CRDT protocol and ECS7

> TODO: Write about resolving assets for models

## Appendix

### Ephemeral keys

Ethereum accounts are globally used in Decentraland to identify the users. Public key cryptography and signatures are leveraged to trust that they (the users) performed an action because they are the only ones capable of [signing](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1271.md) a message. That is the same mechanism used by many other platforms to perform on and off-chain actions.

In order to protect the assets of the community, to keep a reasonable level of trust with user actions, and to enhance the UX of the platform e.g. not needing the users to accept a transaction every time they want to open a door. An [ephemeral key](https://en.wikipedia.org/wiki/Ephemeral_key) is created and signed using their Ethereum account. That establishes a certified trust chain. This way, messages can be signed with the in-memory ephemeral key. Both the initial signature of the ephemeral key by the real account, and the message signed with the ephemeral key are used as the [AuthChain](https://github.com/decentraland/decentraland-crypto) to authorize requests across all services required to make Decentraland work.

### AuthChain

[Agora]: https://agora.decentraland.org (Agora, the first governance app)
[genesis-city]: map.png  "Decentraland's Genesis City"
[Builder]: https://builder.decentraland.org (Decentraland Builder)
[whitepaper]: https://decentraland.org/whitepaper.pdf (Decentraland Whitepaper)
[dao]: https://governance.decentraland.org/ (Decentraland DAO)
[land-contract]: https://etherscan.io/address/0xf87e31492faf9a91b02ee0deaad50d51d56d5d4d
