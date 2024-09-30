// Copyright (c) 2024 WSO2 LLC. (https://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import yPayNetwork.models;

import ballerina/data.jsondata;
import ballerina/http;
import ballerina/log;
import ballerina/time;

# A service representing a network-accessible API
# bound to port `9090`.
service /v1/picasso\-guard/banks/nad/v2 on new http:Listener(9301) {

    # Inbound endpoint of LanakPay ISO 8583 messages.
    #
    # + caller - http caller
    # + req - http request
    # + return - return value description
    isolated resource function get resolution/[string proxyType]/[string proxy](http:Caller caller, http:Request req)
        returns error? {

        string xBusinessMsgId = check req.getHeader("X-Business-Message-Id");
        log:printInfo("Received a resolution request for proxy: " + proxy + " of type: " + proxyType +
                " with business message ID: " + xBusinessMsgId);
        time:Utc utcTime = time:utcNow();
        string utcString = time:utcToString(utcTime);

        models:PrxyLookUpRspnCBFT response = {
            GrpHdr: {
                MsgId: xBusinessMsgId,
                CreDtTm: utcString.toString(),
                MsgSndr: {
                    Agt: {
                        FinInstnId: {
                            Othr: {
                                Id: "****MYKL"
                            }
                        }
                    }
                }
            },
            LkUpRspn: {
                OrgnlId: "",
                OrgnlPrxyRtrvl: {
                    Val: proxy,
                    Tp: proxyType
                },
                RegnRspn: {
                    PrxRspnSts: "ACTC",
                    StsRsnInf: {
                        Cd: "U000",
                        Prtry: ""
                    },
                    Prxy: {
                        Tp: proxyType,
                        Val: proxy
                    },
                Regn: [
                    {
                        RegnId: "0075800025",
                        DsplNm: "Bank Account",
                        Agt: {
                            FinInstnId: {
                                Othr: {
                                    Id: "AIBMMYKLXXX"
                                }
                            }
                        },
                        Acct: {
                            Id: {
                                Othr: {
                                    Id: "111222333444"
                                }
                            },
                            Nm: "ACCOUNT1"
                        },
                        PreAuthrsd: ""
                    },
                    {
                        RegnId: "0075800025",
                        DsplNm: "Bank Account",
                        Agt: {
                            FinInstnId: {
                                Othr: {
                                    Id: "AIBMMYKLXXX"
                                }
                            }
                        },
                        Acct: {
                            Id: {
                                Othr: {
                                    Id: "555666777888"
                                }
                            },
                            Nm: "ACCOUNT2"
                        },
                        PreAuthrsd: ""
                    }
                ]}
            },
            OrgnlGrpInf: {
                OrgnlMsgId: xBusinessMsgId,
                OrgnlMsgNmId: ""
            }
        };
        check caller->respond(response);
    }

    isolated resource function post register(http:Caller caller, http:Request req) returns error? {

        json payload = check req.getJsonPayload();
        log:printInfo("Received a registration request with payload: " + payload.toString());
        models:FundTransfer fundTransferPayload = check jsondata:parseAsType(payload);
        string xBusinessMsgId = check req.getHeader("X-Business-Message-Id");
        models:FundTransferResponse response = {
            data: {
                businessMessageId: xBusinessMsgId,
                createdDateTime: fundTransferPayload.data.createdDateTime,
                code: "ACTC",
                reason: "U000",
                registrationId: "0075800039"
            }
        };
        check caller->respond(response);
    }
}
