//
//  LocalServer.swift
//  Get UDID Local Swift
//
//  Created by Le Tien Dat on 2/25/26.
//

import Foundation
import Network
import SwiftUICore

class LocalServer: ObservableObject {
    enum StatusServer: String {
        case started = "Started"
        case stopped = "Stopped"
        case error = "Error"
    }
    
    enum EndpointServer: String {
        case ping = ""
        case udid = "/udid"
        case installProfile = "/install-profile"
        case success = "/success"
        case error = "/error"

        init(path: String) {
            let cleanPath = path.components(separatedBy: "?").first ?? path

            let normalized = cleanPath.hasSuffix("/") && cleanPath.count > 1
                ? String(cleanPath.dropLast())
                : cleanPath

            self = EndpointServer(rawValue: normalized) ?? .error
        }
    }

    enum StatusGetProfile {
        case success(infoDevice: InfoDevice)
        case none
    }

    private var listener: NWListener?
    private(set) var ipAddress = "127.0.0.1"
    private(set) var port = NWEndpoint.Port(integerLiteral: 2511)
    private(set) var infoDevice: InfoDevice?
    var urlString: String {
        "http://\(ipAddress):\(port.rawValue)"
    }
    private var currentTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    @Published var isRunning = false
    @Published var statusServerMessage: StatusServer = .stopped
    @Published var isInstallingProfile = false
    @Published var log = "Device information will appear here after installing the profile...\n"

    func getPath(endpoint: EndpointServer) -> String {
        urlString + endpoint.rawValue
    }

    func appendLog(_ text: String) {
        DispatchQueue.main.async {
            self.log.append(contentsOf: text + "\n")
        }
    }

    func start() {
        guard !isRunning else { return }

        do {
            let parameters = NWParameters.tcp

            if let localIP = IPv4Address(ipAddress) {
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(localIP), port: port)
            }

            listener = try NWListener(using: parameters)
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        guard let self else { return }
                        self.isRunning = true
                        self.statusServerMessage = .started
                        self.appendLog("Server started with port \(self.port.rawValue)")
                    case .failed(let error):
                        guard let self else { return }
                        self.isRunning = false
                        self.statusServerMessage = .error
                        self.appendLog("Server error: \(error.localizedDescription)")
                        self.stop()
                    case .cancelled:
                        guard let self else { return }
                        self.isRunning = false
                        self.statusServerMessage = .stopped
                        self.appendLog("Server stopped")
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global())
                self?.handleConnection(connection)
            }

            listener?.start(queue: .global(qos: .background))
        } catch {
            DispatchQueue.main.async {
                self.statusServerMessage = .error
                self.appendLog("Error Initializing Server: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        statusServerMessage = .stopped
    }

    func test(completion: @escaping (Bool) -> ()) {
        guard let url = URL(string: getPath(endpoint: .ping)) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0 

        URLSession.shared.dataTask(with: request) { _, _, error in
            DispatchQueue.main.async {
                if error != nil {
                    completion(false)
                    return
                }
                completion(true)
            }
        }.resume()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let rawData = data else { return }

            guard let separator = "\r\n\r\n".data(using: .utf8) else { return }
            
            let headerData: Data
            let bodyData: Data
            
            if let range = rawData.range(of: separator) {
                headerData = rawData.subdata(in: rawData.startIndex..<range.lowerBound)
                bodyData = rawData.subdata(in: range.upperBound..<rawData.endIndex)
            } else {
                headerData = rawData
                bodyData = Data()
            }

            guard let headerString = String(data: headerData, encoding: .utf8) else {
                self.sendError(connection)
                return
            }

            let lines = headerString.components(separatedBy: "\r\n")
            guard let firstLine = lines.first else { return }

            let components = firstLine.components(separatedBy: " ")
            guard components.count >= 2 else { return }

            let path = components[1]
            let method = components[0]
            let endpoint = LocalServer.EndpointServer(path: path)

            switch endpoint {
            case .udid:
                self.serveHandleUDID(connection, requestData: bodyData, method: method) 
            case .installProfile:
                self.serveMobileConfig(connection)
            case .success:
                self.serveSuccess(connection)
            default:
                self.sendError(connection)
            }
        }
    }

    private func serveHandleUDID(_ connection: NWConnection, requestData: Data, method: String) {
        guard method == "POST",
              let startMarker = "<?xml".data(using: .utf8),
              let endMarker = "</plist>".data(using: .utf8),
              let startRange = requestData.range(of: startMarker),
              let endRange = requestData.range(of: endMarker, options: .backwards) else {
            appendLog("Can't parse data.")
            sendError(connection) 
            return
        }
        
        let xmlData = requestData.subdata(in: startRange.lowerBound..<endRange.upperBound)
        do {
            if let plistDict = try PropertyListSerialization.propertyList(from: xmlData, options: [], format: nil) as? [String: Any] {
                let udid = plistDict["UDID"] as? String ?? "NULL"
                let imei = plistDict["IMEI"] as? String ?? "NULL"
                let product = plistDict["PRODUCT"] as? String ?? "NULL"
                let version = plistDict["VERSION"] as? String ?? "NULL"
                let serial = plistDict["SERIAL"] as? String ?? "NULL"

                infoDevice = InfoDevice(udid: udid, imei: imei, product: product, version: version, serial: serial)
                let textLog = """
                
                ========== INFO DEVICE ==========
                \(infoDevice!.description)
                
                Extracted at \(currentTimeString)
                
                """

                DispatchQueue.main.async {
                    self.isInstallingProfile = false
                }
                appendLog(textLog)
                handleResponseSuccess(connection)
            } else {
                appendLog("Can't parse data.")
                sendError(connection)
            }
        } catch {
            appendLog("Parse error: \(error.localizedDescription)")
            sendError(connection)
        }
    }

    private func serveMobileConfig(_ connection: NWConnection) {
        guard let fileURL = Bundle.main.url(forResource: "GetUDID", withExtension: "mobileconfig"),
              let fileData = try? Data(contentsOf: fileURL) else {
            appendLog("Could not read GetUDID.mobileconfig")
            sendError(connection)
            return
        }

        let header = """
            HTTP/1.1 200 OK\r\n\
            Content-Type: application/x-apple-aspen-config\r\n\
            Content-Disposition: attachment; filename="GetUDID.mobileconfig"\r\n\
            Content-Length: \(fileData.count)\r\n\
            Connection: close\r\n\
            \r\n
            """

        var responseData = Data(header.utf8)
        responseData.append(fileData)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
            self.appendLog("The GetUDID.mobileconfig file has been sent to the user's browser. Please download and install it.")
        }))
    }

    private func serveSuccess(_ connection: NWConnection) {
        let html = infoDevice != nil ? htmlString(status: .success(infoDevice: infoDevice!)) : htmlString(status: .none)
        let response = """
        HTTP/1.1 200 OK
        Content-Type: text/html; charset=utf-8
        Content-Length: \(html.utf8.count)
        Connection: close
        
        \(html)
        """

        connection.send(content: Data(response.utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func sendError(_ connection: NWConnection) {
        let html = htmlString(status: .none)
        let response = """
        HTTP/1.1 400 Bad Request
        Content-Type: text/html; charset=utf-8
        Content-Length: \(html.utf8.count)
        Connection: close
        
        \(html)
        """

        connection.send(content: Data(response.utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func handleResponseSuccess(_ connection: NWConnection) {
        let responseString = """
            HTTP/1.1 301 Moved Permanently
            Location: /success
            Content-Length: 0
            Connection: close\r\n\r\n
            """

            let responseData = responseString.data(using: .utf8)!
            connection.send(content: responseData, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
    }

    private func htmlString(status: StatusGetProfile) -> String {
        var title = ""
        var content = ""

        switch status {
        case .success(let data):
            title = "Success"
            content = """
            <h2>Get Info Device Success</h2>
            <p>\(data.description.replacingOccurrences(of: "\n", with: "<br>"))</p>
            <p class="txt-info">Extracted at \(currentTimeString)</p>
            """
        case .none:
            title = "Invalid"
            content = "<p>Invalid!<p>"
        }
        
        return """
        <!DOCTYPE html>
        <html lang="vi">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta name="format-detection" content="telephone=no">
            <title>\(title)</title>
            <style>
                body {
                    margin: 0;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    background: #f2f2f7;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                }
                .container {
                    text-align: center;
                }
                p {
                    font-size: 18px;
                    color: #555;
                }
                .txt-info {
                    font-size: 14px;
                    color: #000;
                }
            </style>
        </head>
        <body>
            <div class="container">
                \(content)
            </div>
        </body>
        </html>
        """
    }
}
