# Apache NiFi Site-to-Site iOS Cocoa Framework 

A lightweight, easy-to-use, Cocoa Framework for sending data to NiFi via the Site-to-Site protocol implemented in Objective-C with primarily Apple-provided Objective-C/C library dependencies. Synchronous and asynchronous interface methods are provided via a low-level site-to-site client and a higher-level site-to-site service that wraps the client. This Cocoa framework will run on iOS devices and simulators.

For the most part, this implementation uses dependencies provided by the Apple platform. The one exception to this is the third-party FMDB, a lightweight SQLite interface, which is used internally by s2s as a mechanism for persistent queuing of flow file data packets when the asynchronous interface is invoked.

## Structure and XCode Schemes

* s2s: iOS Cocoa Framework
* s2sTests: Tests for the s2s iOS Cocoa Framework
* Demo: A Demo app showing basic usage of the s2s iOS Cocoa Framework

## Development Environment Requirements

* A Mac (tested on MacOS 10.12.5)
* XCode (tested with XCode 8)
* [The latest version of Carthage](https://github.com/Carthage/Carthage/releases), a dependency manager used for pulling in FMDB, a third-party framework used by s2s
* An iOS device or simulator (tested on iOS 9 and later, running on iPhone SE simulator device)

## Building

The included XCode Project (nifisitetosite.xcodeproj) can be used for building using the XCode IDE or XCode command-line tools.

The s2s 

Here are the commands for building and running the test suite from the command line:

```shell
carthage bootstrap
xcodebuild test -scheme s2sTests -destination 'platform=iOS Simulator,name=iPhone 7'

```

The first command will run Carthage in the project directory. It uses the top-level Cartfile as its input and will download and build FMDB.
The second command builds s2s and s2sTests, which are run in the specified destination, in this case an iPhone 7 iOS Simulator device.

The included XCode project case also be opened in the XCode IDE, as its own standalone project or added to a workspace containing another project (e.g., the app for which you want to use the s2s framework).

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

NiFiTransactionResult *transactionResult = [transaction confirmAndComplete];
```

### From Swift

As an Objective-C Cocoa Framework, s2s can be imported and used from Swift. 
In order to do this, see Apple's 
[Developer Guide for mixing Objective-C and Swift](https://developer.apple.com/library/content/documentation/Swift/Conceptual/BuildingCocoaApps/MixandMatch.html)

## Demo App and Framework Test Plan

The functionality of this framework is verified by two methods:
* Automated testing via XCode unit tests in the s2sTests target
* Manual testing via included demo app

In addition to verifying functionality, both serve as good examples of 
how to use the framework API.

To run the tests, select 's2sTests' as the active scheme in XCode, switch to the Test Navigator in the left panel, and click the play icon next to a test or test suite to run the tests.

To run the demo app, select 'Demo' as the active scheme in XCode and click the Build and Play scheme button.

## Security

The S2S Framework can use TLS when communicating to a NiFI server, provided the NiFi server is 
configured for secure communication.

If a NiFi server is using a certificate signed by a [trusted root Certificate Authority](https://support.apple.com/en-us/HT204132), 
all that is required is to configure the stie-to-site client to secure = true. HTTPS will be used as the 
transport protocol.

If the NiFi server is using a self-signed certificate, your app using the S2S framework 
must be made aware of the CA. See Apple's documentation for doing this: [https://support.apple.com/en-ca/HT204460].

Client authentication to the NiFi server is currently supported via username and password credentials.

## TODOs and Planned Features
* Local flow file buffering with persistence
* Socket implementation
* Two-way SSL with client certificate
