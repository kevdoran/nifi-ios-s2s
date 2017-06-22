# Apache NiFi Site-to-Site Cocoa Framework (iOS and MacOS)

A lightweight, easy-to-use, Cocoa Framework for sending data to NiFi via the Site-to-Site protocol implemented in Objective-C with only Apple-platform-provided Objective-C/C library dependencies. This Cocoa Framework will run on all major Apple platforms, such as iOS and MacOS.

This is currently a work in progress.

## Structure 

* s2s: iOS Framework
* s2sTests: Tests for the s2s framework
* Demo: The Demo app (currently just a placeholder single-screen app)

## Development Environment Requirements

* A Mac (tested on MacOS 10.12.5)
* XCode (tested with XCode 8)
* An iOS device or simulator (tested on iOS 10 on iPhone SE simulator)

## Building

The included XCode Project can be used for building using XCode (IDE or using command-line tools).

## Usage

### From Objective-C

Here is a basic usage example of the s2s Cocoa Framework from Objective-C.

```objective-c
NiFiSiteToSiteClientConfig * s2sConfig = [[NiFiSiteToSiteClientConfig alloc] init];
s2sConfig.transportProtocol = HTTP;
s2sConfig.host = @"localhost";
s2sConfig.port = [NSNumber numberWithInt:8080];
s2sConfig.portId = @"82f79eb6-015c-1000-d191-ee1ef23b1a74";

id s2sClient = [NiFiSiteToSiteClient clientWithConfig:s2sConfig];

id transaction = [s2sClient createTransaction];

NSDictionary * attributes1 = @{@"packetNumber": @"1"};
NSData * data1 = [@"Data Packet 1" dataUsingEncoding:NSUTF8StringEncoding];
id dataPacket1 = [NiFiDataPacket dataPacketWithAttributes:attributes1 data:data1];
[transaction sendData:dataPacket1];

NSDictionary * attributes2 = @{@"packetNumber": @"2"};
NSData * data2 = [@"Data Packet 2" dataUsingEncoding:NSUTF8StringEncoding];
id dataPacket2 = [NiFiDataPacket dataPacketWithAttributes:attributes2 data:data2];
[transaction sendData:dataPacket2];

NSDictionary * attributes3 = @{@"packetNumber": @"3"};
NSData * data3 = [@"Data Packet 3" dataUsingEncoding:NSUTF8StringEncoding];
id dataPacket3 = [NiFiDataPacket dataPacketWithAttributes:attributes3 data:data3];
[transaction sendData:dataPacket3];

NiFiTransactionResult *transactionResult = [transaction confirmAndComplete];
```

### From Swift

As an Objective-C Cocoa Framework, s2s can be imported and used from Swift. 
In order to do this, see Apple's 
[Developer Guide for mixing Objective-C and Swift](https://developer.apple.com/library/content/documentation/Swift/Conceptual/BuildingCocoaApps/MixandMatch.html)

## TODOs and Planned Features
* Local flow file buffering with persistence
* Socket implementation
* Two-way SSL with client certificate
