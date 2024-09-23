// Copyright 2024 [name of copyright owner]

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

//     http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ballerina/constraint;
import ballerina/http;
import ballerina/mime;
import ballerina/log;
import ballerinax/financial.iso20022;

import drivers.paynet.models;
import digitalpaymentshub/drivers.util;

http:Client paynetClient = check new ("http://localhost:8086/v1/picasso-guard/banks/nad/v2"); // todo move to init function

# Paynet driver service.
# bound to port `9091`.
service http:InterceptableService / on new http:Listener(9091) {

    resource function post transact(http:Caller caller, http:Request req) returns error? {
        
        // Extract the json payload from the request
        json payload = check req.getJsonPayload();
        http:Response response = check handleOutbound(payload);
        // return response;
        check caller->respond(response);
    }

    public function createInterceptors() returns http:Interceptor|http:Interceptor[] {
        return new util:ResponseErrorInterceptor();
    }
}


public function handleInbound(byte[] & readonly data) returns string? {
    return;
};

public function handleOutbound(json payload) returns http:Response|error {

    iso20022:FIToFICstmrCdtTrf|error iso20022ValidatedMsg = constraint:validate(payload);
    // if msg is of type pacs 008
    if (iso20022ValidatedMsg is iso20022:FIToFICstmrCdtTrf) {
        iso20022:FIToFICstmrCdtTrf isoPacs008Msg = check iso20022ValidatedMsg.cloneWithType(iso20022:FIToFICstmrCdtTrf);
        // Differentiate proxy resolution and fund transfer request
        if (isProxyRequest(isoPacs008Msg.SplmtryData)) {
            // proxy resolution request to PayNet
            models:PrxyLookUpRspnCBFT|error paynetProxyResolution = getProxyResolution(isoPacs008Msg);
            if (paynetProxyResolution is error) {
                log:printError("Error while resolving proxy: " + paynetProxyResolution.message());
                return error("Error while resolving proxy: " + paynetProxyResolution.message());
            }
            // transform to iso 20022 response pacs 002.001.14
            iso20022:FIToFIPmtStsRpt iso20022Response = transformPrxy004toPacs002(paynetProxyResolution);
            // add original msg id
            iso20022Response.GrpHdr.MsgId = isoPacs008Msg.GrpHdr.MsgId;
            http:Response httpResponse = new;
            httpResponse.setPayload(iso20022Response.toJsonString());
            return httpResponse;
        } else {
            // fund transfer request 
            models:fundTransferResponse|error paynetProxyRegistartionResponse = 
                postPaynetProxyRegistration(isoPacs008Msg);
            if (paynetProxyRegistartionResponse is error) {
                log:printError("Error while registering proxy: " + paynetProxyRegistartionResponse.message());
                return error("Error while registering proxy: " + paynetProxyRegistartionResponse.message());
            }
            // transform to iso 20022 response pacs 002.001.14
            iso20022:FIToFIPmtStsRpt iso20022Response = 
                transformFundTransferResponsetoPacs002(paynetProxyRegistartionResponse, isoPacs008Msg);

            http:Response httpResponse = new;
            httpResponse.setPayload(iso20022Response.toJsonString());
            return httpResponse;
        }
    } else {
        // only proxy resolution and fund transfer requests are supported
        log:printError("Request type not supported");
        return error("Request type not supported");
    }
}

function getProxyResolution(iso20022:FIToFICstmrCdtTrf isoPacs008Msg) returns models:PrxyLookUpRspnCBFT|error {
    
    string bicCode = isoPacs008Msg.CdtTrfTxInf[0].DbtrAcct?.Id?.Othr?.Id ?: "";
    iso20022:SplmtryData[]? supplementaryData = isoPacs008Msg.SplmtryData;
    string proxyType = resolveProxyType(supplementaryData);
    string proxy = resolveProxy(supplementaryData);

    if (bicCode == "" || proxyType == "" || proxy == "") {
        return error("Error while resolving proxy. Required data not found");
    }

    string xBusinessMsgId = check generateXBusinessMsgId(bicCode);
    models:PrxyLookUpRspnCBFT response = check paynetClient->/resoluion/[proxyType]/[proxy]({
        Accept: mime:APPLICATION_JSON,
        Authorization: "Bearer 12345-6789",
        "X-Business-Message-Id": xBusinessMsgId,
        "X-Client-Id": "123456",
        "X-Gps-Coordinates": "3.1234, 101.1234",
        "X-Ip-Address": "172.110.12.10"
    });
    log:printDebug("Response received from Paynet: " + response.toBalString());
    return response;
}

function postPaynetProxyRegistration(iso20022:FIToFICstmrCdtTrf isoPacs008Msg) 
    returns models:fundTransferResponse|error {

    models:fundTransfer|error proxyRegistrationPayload = transformPacs008toFundTransfer(isoPacs008Msg);
    if proxyRegistrationPayload is models:fundTransfer {
        string bicCode = isoPacs008Msg.CdtTrfTxInf[0].DbtrAcct?.Id?.Othr?.Id ?: "";
        string xBusinessMsgId = check generateXBusinessMsgId(bicCode);
        map<string> headers = {
            Accept: mime:APPLICATION_JSON,
            Authorization: "Bearer 12345-6789",
            "X-Business-Message-Id": xBusinessMsgId,
            "X-Client-Id": "123456",
            "X-Gps-Coordinates": "3.1234, 101.1234",
            "X-Ip-Address": "172.10.100.23"
        };
        models:fundTransferResponse response = check paynetClient->post("/register", proxyRegistrationPayload, headers);
        log:printDebug("Response received from Paynet: " + response.toBalString());
        return response;
    } else {
        log:printError("Error while building proxy registration payload: " + proxyRegistrationPayload.message());
        return error("Error while building proxy registration payload: " + proxyRegistrationPayload.message());
    }
};
