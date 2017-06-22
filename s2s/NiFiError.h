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

#ifndef NiFiError_h
#define NiFiError_h

#import <Foundation/NSError.h>

FOUNDATION_EXPORT NSErrorDomain const NiFiErrorDomain;

/*!
 @enum NiFi-related Error Codes
 @abstract Constants used by NSError to indicate errors in the NiFi domain
 */
NS_ENUM(NSInteger)
{
    NiFiErrorUnknown = -1,
    
    // HTTP Errors
    NiFiErrorHttpStatusCode = 1000, // note, 1000-1999 are reserved for errors relating to HTTP status codes
                                    // to pass the HTTP Status code in the error code, you can add it to this,
                                    // e.g., 404 becomes 1404 (= 1000 + 404)
    
    // Site-to-Site
    NiFiErrorSiteToSiteClient = 2000,
    
    // Transaction
    NiFiErrorSiteToSiteTransaction = 3000,
    
    // HTTP Rest API Client
    NiFiErrorHttpRestApiClient = 4000,
    NiFiErrorHttpRestApiClientCouldNotFormURL = 4001
    
};

#endif /* NiFiError_h */
