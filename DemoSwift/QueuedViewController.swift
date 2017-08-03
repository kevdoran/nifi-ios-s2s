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

import UIKit

import s2s

class QueuedViewController: UIViewController {
    
    let SECONDS_TO_NANOS = 1000000000
    let queueProcessingInterval = TimeInterval(5.0)
    var queueProcessingTimer: Timer!
    var s2sClientConfig: NiFiQueuedSiteToSiteClientConfig!
    
    
    var buttonClicksSinceLoad = 0;
    var amount = 10;
    @IBOutlet var amountLabel: UILabel!
    @IBOutlet var amountSlider: UISlider!
    @IBOutlet var queueCountLabel: UILabel!
    @IBOutlet var queueCountCapacityBar: UIProgressView!
    @IBOutlet var queueProcessingSwitch: UISwitch!
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        queueProcessingTimer.invalidate()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        s2sClientConfig = NiFiQueuedSiteToSiteClientConfig()
        let nifiURL = URL(string: UserDefaults.standard.string(forKey: "nifi.s2s.config.cluster.url")!)
        let s2sRemoteCluster = NiFiSiteToSiteRemoteClusterConfig(url: nifiURL!)
        if let username = UserDefaults.standard.string(forKey: "nifi.s2s.config.secure.username"),
            let password = UserDefaults.standard.string(forKey: "nifi.s2s.config.secure.password") {
            s2sRemoteCluster?.username = username
            s2sRemoteCluster?.password = password
        }
        s2sRemoteCluster?.urlSessionConfiguration = AppNetworkingUtils.demoUrlSessionConfiguration()
        s2sRemoteCluster?.urlSessionDelegate = AppURLSessionDelegate()
        s2sClientConfig.addRemoteCluster(s2sRemoteCluster!)
        if let portName = UserDefaults.standard.string(forKey: "nifi.s2s.config.portName") {
            s2sClientConfig.portName = portName
        }
        if let portId = UserDefaults.standard.string(forKey: "nifi.s2s.config.portId") {
            s2sClientConfig.portId = portId
        }
        
        s2sClientConfig.maxQueuedPacketCount = NSNumber(
            value: UserDefaults.standard.integer(forKey: "nifi.s2s.config.queued.max_queued_packet_count"))
        s2sClientConfig.maxQueuedPacketSize = NSNumber(
            value: UserDefaults.standard.integer(forKey: "nifi.s2s.config.queued.max_queued_packet_size"))
        s2sClientConfig.preferredBatchCount = NSNumber(
            value: UserDefaults.standard.integer(forKey: "nifi.s2s.config.queued.preferred_batch_count"))
        s2sClientConfig.preferredBatchSize = NSNumber(
            value: UserDefaults.standard.integer(forKey: "nifi.s2s.config.queued.preferred_batch_size"))
        
        s2sClientConfig.peerUpdateInterval = 60.0 // seconds, outside of a demo scenario this should probably be set higher.
        
        s2sClientConfig.dataPacketPrioritizer = NiFiNoOpDataPacketPrioritizer(fixedTTL: 60.0)
        
        // Other setup
        updateCreationAmount()
        
        // Register for UI events
        queueProcessingSwitch.addTarget(self, action: #selector(queueProcessingSwitchChanged), for: UIControlEvents.valueChanged)
    }
    
    
    
    func updateCreationAmount() {
        amount = Int(amountSlider.value * s2sClientConfig.maxQueuedPacketCount.floatValue)
        if (amount <= 0) {
            amount = 1;
        }
        amountLabel.text = String(amount);
    }
    
    @IBAction func amountSliderValueChanged(_ sender: Any) {
        updateCreationAmount()
    }
    
    @IBAction func enqueueButtonClicked(_ sender: Any) {
        buttonClicksSinceLoad += 1
        
        updateCreationAmount()
        let dataPackets = NSMutableArray(capacity: amount)
        for i in 0...amount-1 {
            dataPackets[i] = NiFiDataPacket(attributes: ["clickEvent": String(buttonClicksSinceLoad),
                                                         "packetNumber": String(i)],
                                            data: "This is the content of the data packet".data(using: String.Encoding.utf8))
        }
        NiFiSiteToSiteService.enqueueDataPackets(dataPackets as! [Any], config: s2sClientConfig, completionHandler: queuedOperationCompleted)
    }
    
    func queueProcessingSwitchChanged() {
        if(queueProcessingSwitch.isOn) {
            queueProcessingTimer = Timer.scheduledTimer(timeInterval: queueProcessingInterval,
                                                        target: self,
                                                        selector: #selector(cleanAndProcessQueue),
                                                        userInfo: nil,
                                                        repeats: true)
        } else {
            queueProcessingTimer.invalidate()
        }
    }
    
    func cleanAndProcessQueue() {
        NSLog("Cleaning and processing NiFi SiteToSite queue")
        // Cleanup deletes queued packets based on maxQueueCount or maxQueueSize or if packets are older than their TTL
        NiFiSiteToSiteService.cleanupQueuedPackets(with: self.s2sClientConfig,
                                                   completionHandler: self.queuedOperationCompleted)
        
        // Process sends the next batch (based on configured batchCount or batchSize) to the remote NiFi
        NiFiSiteToSiteService.processQueuedPackets(with: self.s2sClientConfig,
                                                   completionHandler: self.queuedOperationCompleted)
    }
    
    func queuedOperationCompleted(status: NiFiSiteToSiteQueueStatus?, error: Error?) {
        if (status != nil) {
            NSLog("Received NiFi background queue operation callback. queueCount=%i, queueSize=%iB, queueIsFull=%@",
                  status!.queuedPacketCount, status!.queuedPacketSizeBytes, status!.isFull.description)
            
            DispatchQueue.main.async {
                // Update Queue Count Label
                self.queueCountLabel.text = String(status!.queuedPacketCount)
                
                // Update Queue Count Capacity Bar
                let queueCountCapacityFraction = (Float(status!.queuedPacketCount) / Float(self.s2sClientConfig.maxQueuedPacketCount))
                self.queueCountCapacityBar.setProgress(queueCountCapacityFraction, animated: true)
                self.view.setNeedsDisplay()
            }
            
        } else if (error != nil) {
            NSLog("Received NiFi background queue operation callback. Operation encountered error: %@",
                  error!.localizedDescription)
        } else {
            NSLog("Received NiFi background queue operation callback. Status or Error unknown (null).")
        }
    }
    
}



