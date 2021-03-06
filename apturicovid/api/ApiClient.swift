import Foundation
import RxSwift
import DeviceCheck

class ApiClient: RestClient {
    static let shared = ApiClient()
    
    private func obtainDeviceToken() -> Observable<String> {
        return Observable.create { (observer) -> Disposable in
            let currentDevice = DCDevice.current
            guard currentDevice.isSupported else {
                observer.onError(NSError.make("DC: Device unsupported"))
                return Disposables.create()
            }
            
            currentDevice.generateToken { (data, error) in
                if let error = error {
                    observer.onError(error)
                } else {
                    data.map {
                        observer.onNext($0.base64EncodedString())
                    }
                }
            }
            return Disposables.create()
        }
    }
    
    private func makePhoneVerificationCall(phoneNumber: String, deviceToken: String) -> Observable<PhoneVerificationRequestResponse?> {
        let encoder = JSONEncoder()
        let body = try? encoder.encode(PhoneVerificationRequest(phone_number: phoneNumber, device_check_token: deviceToken))
        
        guard body?.isEmpty == false else {
            return Observable.error(NSError.make("Error creating request"))
        }
        
        return request(urlString: "\(baseUrl)/phone_verifications", body: body!, method: "POST")
            .map { (data) -> PhoneVerificationRequestResponse? in
                return try? JSONDecoder().decode(PhoneVerificationRequestResponse.self, from: data)
        }
    }
    
    func requestPhoneVerification(phoneNumber: String) -> Observable<PhoneVerificationRequestResponse?> {
        return obtainDeviceToken()
            .flatMap { (deviceToken) -> Observable<PhoneVerificationRequestResponse?> in
                return self.makePhoneVerificationCall(phoneNumber: phoneNumber, deviceToken: deviceToken)
        }
    }
    
    func requestPhoneConfirmation(token: String, code: String) -> Observable<PhoneConfirmationResponse?> {
        let encoder = JSONEncoder()
        let body = try? encoder.encode(PhoneConfirmationRequest(token: token, code: code))
        
        guard body?.isEmpty == false else {
            return Observable.error(NSError.make("Error creating request"))
        }
        
        return request(urlString: "\(baseUrl)/phone_verifications/verify", body: body!, method: "POST")
            .map { (data) -> PhoneConfirmationResponse? in
                return try? JSONDecoder().decode(PhoneConfirmationResponse.self, from: data)
        }
    }
}
