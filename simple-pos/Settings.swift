//
//  Settings.swift
//  simple-pos
//
//  Created by Wayne Carter on 5/22/24.
//

import Foundation
import Combine

class Settings: ObservableObject {
    static let shared = Settings()
    
    @Published var endpoint: AppService.Endpoint?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Observe UserDefaults changes
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.updateEndpoint()
            }
            .store(in: &cancellables)
        
        updateEndpoint()
    }
    
    private func updateEndpoint() {
        let userDefaults = UserDefaults.standard
        var newEndpoint: AppService.Endpoint?
        
        // If the endpoint is enabled, get it's config
        if userDefaults.bool(forKey: "endpoint_enabled"),
           let endpointUrlString = userDefaults.string(forKey: "endpoint_url"),
           let endpointUrl = URL(string: endpointUrlString)
        {
            newEndpoint = AppService.Endpoint(
                url: endpointUrl,
                username: userDefaults.string(forKey: "endpoint_username"),
                password: userDefaults.string(forKey: "endpoint_password")
            )
        }
        
        // If the endpoint has changed, update it
        if newEndpoint != endpoint {
            endpoint = newEndpoint
        }
    }
}
