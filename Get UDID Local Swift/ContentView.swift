//
//  ContentView.swift
//  Get UDID Local Swift
//
//  Created by Le Tien Dat on 2/25/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var localServer = LocalServer()

    @Environment(\.openURL) var openURL
    
    var body: some View {
        VStack {
            VStack(spacing: 16) {
                Text("HTTP Server Status: \(localServer.statusServerMessage.rawValue)")
                    .foregroundStyle(localServer.isRunning ? .green : .red)
                    .padding(.bottom, 8)
                    .font(.system(size: 17))
                
                HStack {
                    Button { 
                        handleStartServer()
                    } label: { 
                        Text("Start Server")
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(localServer.isRunning)
                    Spacer(minLength: 16)
                    Button { 
                        handleStopServer()
                    } label: { 
                        Text("Stop Server")
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!localServer.isRunning)
                    Spacer(minLength: 16)
                    Button { 
                        handleTest()
                    } label: { 
                        Text("Test")
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!localServer.isRunning)
                }
                Button(action: { 
                    handleInstallProfile()
                }) {
                    Spacer()
                    Text("Install Profile to Get UDID")
                        .foregroundStyle(.white)
                        .padding(.vertical, 4)
                    Spacer()
                }
                .buttonStyle(.borderedProminent)
    
                ScrollView {
                    Text(localServer.log)
                        .font(.custom("Menlo", size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                )
                .scrollIndicators(.automatic)
            }
            .padding(.top, 60)
            Spacer()
        }
        .padding(.horizontal, 16)
        .font(.system(size: 15))
        .alert("Profile Loading", isPresented: $localServer.isInstallingProfile) {
            Button("OK", role: .cancel) {
                localServer.isInstallingProfile = false
            }
        } message: {
            Text("The configuration profile is being loaded in Safari. Please follow the iOS prompts to install it. The app will automatically receive device information after installation.")
        }
    }

    private func handleStartServer() {
        guard !localServer.isRunning else { return }
        localServer.start()
    }
    
    private func handleStopServer() {
        guard localServer.isRunning else { return }
        localServer.stop()
    }

    private func handleTest() {
        guard localServer.isRunning else { 
            localServer.appendLog("Test fail! Server not started yet.")
            return
        }

        localServer.test { result in
            let path = localServer.getPath(endpoint: .ping)
            if result {
                localServer.appendLog("Ping to \(path) successful!")
            } else {
                localServer.appendLog("Ping to \(path) failed!")
            }
        }
    }

    private func handleInstallProfile() {
        guard localServer.isRunning else { 
            localServer.appendLog("Server not started yet.")
            return
        }

        let path = localServer.getPath(endpoint: .installProfile)
        guard let url = URL(string: path) else {
            localServer.appendLog("Cound not create URL \(path).")
            return
        }

        openURL(url) { accepted in
            if accepted {
                localServer.appendLog("Opening Safari with URL: \(path)")
                localServer.isInstallingProfile = true
            } else {
                localServer.appendLog("Could not open Safari with URL: \(path)")
            }
        }
    }
}

#Preview {
    ContentView()
}
