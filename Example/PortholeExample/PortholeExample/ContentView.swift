//
//  ContentView.swift
//  PortholeExample
//
//  Created by Sohan Jain on 18/07/26.
//

import SwiftUI
import Atlantis

struct ContentView: View {
    @State private var isShowingTraffic = false

    var body: some View {
        VStack(spacing: 16) {
           
            Image(systemName: "wifi")
            
            Text("Porthole")
                .font(.title)

            Button("Make Example API Calls") {
                makeExampleAPICalls()
            }

            Button("View Traffic") {
                isShowingTraffic = true
            }
        }
        .padding()
        .sheet(isPresented: $isShowingTraffic) {
            NavigationStack {
                AtlantisTrafficListView()
                    .navigationTitle("Traffic")
            }
        }
    }

    private func makeExampleAPICalls() {
        let urls = [
            "https://jsonplaceholder.typicode.com/posts/1",
            "https://jsonplaceholder.typicode.com/users",
            "https://httpbin.org/status/404",
        ]
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            URLSession.shared.dataTask(with: url).resume()
        }

        if let url = URL(string: "https://jsonplaceholder.typicode.com/posts") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "title": "Porthole",
                "body": "example post",
                "userId": 1,
            ])
            URLSession.shared.dataTask(with: request).resume()
        }
    }
}

#Preview {
    ContentView()
}
