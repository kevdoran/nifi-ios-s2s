/*
 * Copyright 2017 Hortonworks, Inc.
 * All rights reserved.
 *
 *   Hortonworks, Inc. licenses this file to you under the Apache License, Version 2.0
 *   (the "License"); you may not use this file except in compliance with
 *   the License. You may obtain a copy of the License at
 *   http://www.apache.org/licenses/LICENSE-2.0
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 *
 * See the associated NOTICE file for additional information regarding copyright ownership.
 */

#import "ViewController.h"
#import "s2s.h"

@interface ViewController ()
@property NSInteger totalFlowFileCount;
@property (strong, nullable) NiFiSiteToSiteClient *s2sClient;
@property (strong, nullable, atomic) NSURLSession *urlSession;
@end

@interface URLSessionAuthenticatorDelegate : NSObject <NSURLSessionDelegate>
- (instancetype)init;
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[self view] setBackgroundColor:[UIColor colorWithRed:217.0f/255.0f green:217.0f/255.0f blue:217.0f/255.0f alpha:1.0]];
    
    // TODO, load this config from plist file
    NiFiSiteToSiteClientConfig * s2sConfig = [[NiFiSiteToSiteClientConfig alloc] init];
    s2sConfig.transportProtocol = HTTP;
    s2sConfig.host = @"localhost";
    //s2sConfig.port = [NSNumber numberWithInt:8080];
    //s2sConfig.portId = @"82f79eb6-015c-1000-d191-ee1ef23b1a74";
    s2sConfig.port = [NSNumber numberWithInt:32794];
    s2sConfig.portId = @"cb655af6-015c-1000-4b7c-e344b815744d";
    s2sConfig.secure = true;
    s2sConfig.username = @"admin";
    s2sConfig.password = @"admin-password";
    
    _totalFlowFileCount = 0;
    _s2sClient = [NiFiSiteToSiteClient clientWithConfig:s2sConfig];
    // Configured client is now ready to create transactions
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)handleSendButtonClick:(id)sender {
    
    // Make sure we can do the requested action
    if (_s2sClient == nil) {
        return;
    }
    if (_userTextField.text == nil) {
        return;
    }
    
    // Create a NSURLSession that with handle authenticating our server
    if (_urlSession == nil) {
        NSURLSessionConfiguration *urlSessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        NSObject <NSURLSessionDelegate> *delegateAuthenticator = [[URLSessionAuthenticatorDelegate alloc] init];
        _urlSession = [NSURLSession sessionWithConfiguration:urlSessionConfig
                                                    delegate:delegateAuthenticator
                                               delegateQueue:nil];
    }
    
    // Create Site-to-Site Transaction
    id transaction = [_s2sClient createTransactionWithURLSession:_urlSession];
    
    // Send Data Packet(s) over Transaction
    NiFiDataPacket *textFlowFile = [NiFiDataPacket dataPacketWithString:_userTextField.text];
    [transaction sendData:textFlowFile];
    
    // Complete Transaction
    NiFiTransactionResult *result = [transaction confirmAndCompleteOrError:nil];
    
    // Update Flow File counter and View lable
    _totalFlowFileCount += result.dataPacketsTransferred;
    _ffCountLabel.text = [NSString stringWithFormat:@"%ld flow files sent so far", (long)_totalFlowFileCount];
}


@end

// Below you will find a simple example of a NSURLSessionDelegate that will accept self-signed certificates.
// This is for Demo purposes only and should not be used in production as it is not secure.
// In production, it is recommended to use a certificate signed by a trusted root Certificate Authority, which
// will not require implementing your own idenitity verification methods (i.e., https when using a CA-signed
// certificate will "just work".
// For more information, please see Apple's developer documentation:
// https://developer.apple.com/library/content/technotes/tn2232/_index.html

@implementation URLSessionAuthenticatorDelegate
- (instancetype)init {
    self = [super init];
    if (self != nil) {
        // additional init
    }
    return self;
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * _Nullable credential))completionHandler {
    completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialWithUser:@"admin" password:@"admin-password" persistence:NSURLCredentialPersistenceForSession]);
}
@end

