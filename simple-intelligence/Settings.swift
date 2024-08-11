//
//  Settings.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 5/22/24.
//

import Foundation
import Combine

class Settings: ObservableObject {
    static let shared = Settings()
    
    @Published var frontCameraEnabled: Bool = false
    @Published var externalScreenEnabled: Bool = true
    
    @Published var endpoint: Endpoint?
    @Published var useCase: UseCase = .pointOfSale
    @Published var isDemoEnabled: Bool = false {
        didSet {
            let userDefaults = UserDefaults.standard
            userDefaults.setValue(isDemoEnabled, forKey: "demo_enabled")
        }
    }
    
    @Published var isLoggedIn: Bool = false
    
    enum UseCase: String {
        case itemLookup, pointOfSale, bookingLookup
    }
    
    struct Endpoint: Equatable {
        let url: URL
        let username: String?
        let password: String?

        static func == (lhs: Endpoint, rhs: Endpoint) -> Bool {
            return lhs.url == rhs.url &&
                   lhs.username == rhs.username &&
                   lhs.password == rhs.password
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Register defaults
        UserDefaults.standard.register(defaults: [
            "front_camera_enabled": false,
            "external_screen_enabled": false,
            "use_case": UseCase.itemLookup.rawValue,
            "demo_enabled": false
        ])
        
        // Observe UserDefaults changes
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.updateSettings()
            }
            .store(in: &cancellables)
        
        updateSettings()
    }
    
    deinit {
        cancellables.removeAll()
    }
    
    private func updateSettings() {
        updateCamera()
        updateExternalScreen()
        updateEndpoint()
        updateDemo()
        updateIsLoggedIn()
    }
    
    private func updateCamera() {
        let userDefaults = UserDefaults.standard
        let newFrontCameraEnabled = userDefaults.bool(forKey: "front_camera_enabled")
        
        if frontCameraEnabled != newFrontCameraEnabled {
            frontCameraEnabled = newFrontCameraEnabled
        }
    }
    
    private func updateExternalScreen() {
        let userDefaults = UserDefaults.standard
        let newExternalScreenEnabled = userDefaults.bool(forKey: "external_screen_enabled")
        
        if externalScreenEnabled != newExternalScreenEnabled {
            externalScreenEnabled = newExternalScreenEnabled
        }
    }
    
    private func updateEndpoint() {
        let userDefaults = UserDefaults.standard
        var newEndpoint: Endpoint?
        
        // If the endpoint is enabled, get it's config
        if userDefaults.bool(forKey: "endpoint_enabled"),
           let endpointUrlString = userDefaults.string(forKey: "endpoint_url"),
           let endpointUrl = URL(string: endpointUrlString)
        {
            newEndpoint = Endpoint(
                url: endpointUrl,
                username: userDefaults.string(forKey: "endpoint_username"),
                password: userDefaults.string(forKey: "endpoint_password")
            )
        }
        
        if newEndpoint != endpoint {
            endpoint = newEndpoint
        }
    }
    
    private func updateDemo() {
        let userDefaults = UserDefaults.standard
        let isDemoEnabled = userDefaults.bool(forKey: "demo_enabled")
        let useCase: UseCase
        
        if isDemoEnabled {
            let demoUseCaseRawValue = userDefaults.string(forKey: "use_case") ?? UseCase.itemLookup.rawValue
            useCase = UseCase(rawValue: demoUseCaseRawValue) ?? .itemLookup
        } else {
            useCase = .itemLookup
        }
        
        if self.useCase != useCase {
            self.useCase = useCase
        }
        
        if self.isDemoEnabled != isDemoEnabled {
            self.isDemoEnabled = isDemoEnabled
        }
    }
    
    private func updateIsLoggedIn() {
        let isDemoEnabled = self.isDemoEnabled
        let isEndpointEnabled = self.endpoint != nil
        
        isLoggedIn = isDemoEnabled || isEndpointEnabled
    }
}
