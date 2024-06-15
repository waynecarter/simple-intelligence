//
//  Settings.swift
//  simple-search
//
//  Created by Wayne Carter on 5/22/24.
//

import Foundation
import Combine

class Settings: ObservableObject {
    static let shared = Settings()
    
    @Published var endpoint: Endpoint?
    @Published var frontCameraEnabled: Bool = false
    @Published var useCase: UseCase = .pointOfSale
    
    enum UseCase: String {
        case pointOfSale, itemLookup
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
            "use_case": UseCase.pointOfSale.rawValue
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
        updateEndpoint()
        updateCamera()
        updateUseCase()
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
    
    private func updateCamera() {
        let userDefaults = UserDefaults.standard
        let newFrontCameraEnabled = userDefaults.bool(forKey: "front_camera_enabled")
        
        if frontCameraEnabled != newFrontCameraEnabled {
            frontCameraEnabled = newFrontCameraEnabled
        }
    }
    
    private func updateUseCase() {
        let userDefaults = UserDefaults.standard
        let useCaseRawValue = userDefaults.string(forKey: "use_case") ?? UseCase.pointOfSale.rawValue
        let newUseCase: UseCase = UseCase(rawValue: useCaseRawValue) ?? .pointOfSale
        
        if useCase != newUseCase {
            useCase = newUseCase
        }
    }
}
