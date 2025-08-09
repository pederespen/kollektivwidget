import Foundation

struct EnturAPI {
    static let baseURL = "https://api.entur.io/journey-planner/v3/graphql"
    static let geocoderURL = "https://api.entur.io/geocoder/v1/search"
    
    struct DepartureResponse: Codable {
        let data: DataContainer
        
        struct DataContainer: Codable {
            let stopPlace: StopPlace?
        }
        
        struct StopPlace: Codable {
            let id: String
            let name: String
            let estimatedCalls: [EstimatedCall]
        }
        
        struct EstimatedCall: Codable {
            let expectedDepartureTime: String?
            let destinationDisplay: DestinationDisplay
            let serviceJourney: ServiceJourney
            
            struct DestinationDisplay: Codable {
                let frontText: String
            }
            
            struct ServiceJourney: Codable {
                let line: Line
                
                struct Line: Codable {
                    let publicCode: String
                    let name: String
                    let transportMode: String
                    let transportSubmode: String
                }
            }
        }
    }
    
    static func getDepartures(stopId: String) async throws -> [Departure] {
        let query = """
        {
            stopPlace(id: "\(stopId)") {
                id
                name
                estimatedCalls(numberOfDepartures: 20) {
                    expectedDepartureTime
                    destinationDisplay {
                        frontText
                    }
                    serviceJourney {
                        line {
                            publicCode
                            name
                            transportMode
                            transportSubmode
                        }
                    }
                }
            }
        }
        """
        
        let requestBody = ["query": query]
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(DepartureResponse.self, from: data)
        
        guard let stopPlace = response.data.stopPlace else {
            return []
        }
        
        return stopPlace.estimatedCalls.compactMap { call in
            guard let expectedDepartureTime = call.expectedDepartureTime,
                  let departureDate = ISO8601DateFormatter().date(from: expectedDepartureTime) else {
                return nil
            }
            
            return Departure(
                line: call.serviceJourney.line.publicCode,
                destination: call.destinationDisplay.frontText,
                departureTime: departureDate,
                transportMode: call.serviceJourney.line.transportMode,
                stopName: stopPlace.name
            )
        }
    }
    
    // MARK: - Stop Search
    
    struct SearchResponse: Codable {
        let features: [Feature]
        
        struct Feature: Codable {
            let properties: Properties
            
            struct Properties: Codable {
                let id: String
                let name: String
                let label: String
                let category: [String]?
                
                var isTransitStop: Bool {
                    guard let categories = category else { return false }
                    let transitCategories = ["onstreetBus", "onstreetTram", "metroStation", "railStation", "ferryStop"]
                    return categories.contains { transitCategories.contains($0) }
                }
            }
        }
    }
    
    static func searchStops(query: String) async throws -> [StopSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        var components = URLComponents(string: geocoderURL)!
        components.queryItems = [
            URLQueryItem(name: "text", value: query),
            URLQueryItem(name: "size", value: "10"),
            URLQueryItem(name: "lang", value: "no")
        ]
        
        guard let url = components.url else {
            throw NSError(domain: "InvalidURL", code: 0, userInfo: nil)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        
        return response.features
            .filter { $0.properties.isTransitStop && $0.properties.id.hasPrefix("NSR:StopPlace:") }
            .map { feature in
                StopSearchResult(
                    id: feature.properties.id,
                    name: feature.properties.name,
                    label: feature.properties.label
                )
            }
    }
    
    static func getAvailableLines(stopId: String, stopName: String) async throws -> [TransitLine] {
        print("📡 EnturAPI.getAvailableLines called for \(stopId)")
        
        let query = """
        {
            stopPlace(id: "\(stopId)") {
                id
                name
                estimatedCalls(numberOfDepartures: 50) {
                    destinationDisplay {
                        frontText
                    }
                    serviceJourney {
                        line {
                            publicCode
                            name
                            transportMode
                            transportSubmode
                        }
                    }
                }
            }
        }
        """
        
        let requestBody = ["query": query]
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        print("🌐 Making GraphQL request to \(baseURL)")
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Debug: print raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📥 Raw API response: \(jsonString.prefix(500))...")
        }
        
        let response = try JSONDecoder().decode(DepartureResponse.self, from: data)
        print("✅ Successfully decoded response")
        
        guard let stopPlace = response.data.stopPlace else {
            print("⚠️ No stopPlace in response")
            return []
        }
        
        print("🚏 Stop place: \(stopPlace.name), estimated calls: \(stopPlace.estimatedCalls.count)")
        
        // Group by line + destination to get unique routes
        var uniqueLines = Set<String>()
        var lines: [TransitLine] = []
        
        for call in stopPlace.estimatedCalls {
            let lineKey = "\(call.serviceJourney.line.publicCode)-\(call.destinationDisplay.frontText)"
            
            if !uniqueLines.contains(lineKey) {
                uniqueLines.insert(lineKey)
                
                let line = TransitLine(
                    id: "\(stopId)-\(lineKey)",
                    stopId: stopId,
                    stopName: stopName,
                    lineCode: call.serviceJourney.line.publicCode,
                    lineName: call.serviceJourney.line.name,
                    destination: call.destinationDisplay.frontText,
                    transportMode: call.serviceJourney.line.transportMode,
                    transportSubmode: call.serviceJourney.line.transportSubmode,
                    notificationsEnabled: false,
                    notificationLeadTime: 5
                )
                
                lines.append(line)
                print("➕ Added line: \(line.displayName)")
            }
        }
        
        // Sort by transport mode (metro, tram, bus) and then by line number
        return lines.sorted { line1, line2 in
            let order1 = transportModeOrder(line1.transportMode)
            let order2 = transportModeOrder(line2.transportMode)
            
            if order1 != order2 {
                return order1 < order2
            }
            
            // If same transport mode, sort by line code numerically if possible
            if let num1 = Int(line1.lineCode), let num2 = Int(line2.lineCode) {
                return num1 < num2
            }
            
            return line1.lineCode < line2.lineCode
        }
    }
    
    static func getDeparturesForLine(line: TransitLine) async throws -> [Departure] {
        let departures = try await getDepartures(stopId: line.stopId)
        
        // Filter departures for this specific line and destination
        return departures.filter { departure in
            departure.line == line.lineCode && 
            departure.destination == line.destination
        }
    }
    
    private static func transportModeOrder(_ mode: String) -> Int {
        switch mode.lowercased() {
        case "metro": return 1
        case "tram": return 2
        case "bus": return 3
        default: return 4
        }
    }
}

struct Departure {
    let line: String
    let destination: String
    let departureTime: Date
    let transportMode: String
    let stopName: String
    
    var transportSymbolName: String {
        switch transportMode.lowercased() {
        case "bus": return "bus"
        case "tram": return "tram"
        case "metro": return "tram.fill.tunnel"
        case "train": return "train.side.front.car"
        case "ferry": return "ferry"
        default: return "bus"
        }
    }
    
    func minutesUntilDeparture() -> Int {
        let now = Date()
        let timeInterval = departureTime.timeIntervalSince(now)
        return Int(timeInterval / 60)
    }
    
    func shouldNotify(leadTimeMinutes: Int) -> Bool {
        let minutesUntil = minutesUntilDeparture()
        return minutesUntil <= leadTimeMinutes && minutesUntil > 0
    }
}

struct StopSearchResult: Identifiable {
    let id: String
    let name: String
    let label: String
}

struct TransitLine: Identifiable, Codable {
    let id: String // Combination of stopId + lineCode + destination
    let stopId: String
    let stopName: String
    let lineCode: String
    let lineName: String
    let destination: String
    let transportMode: String
    let transportSubmode: String
    var notificationsEnabled: Bool?
    var notificationLeadTime: Int?
    
    var displayName: String {
        "\(lineCode) to \(destination)"
    }
    
    var transportSymbolName: String {
        switch transportMode.lowercased() {
        case "bus": return "bus"
        case "tram": return "tram"
        case "metro": return "tram.fill.tunnel"
        case "train": return "train.side.front.car"
        case "ferry": return "ferry"
        default: return "bus"
        }
    }

    var effectiveLeadTimeMinutes: Int { notificationLeadTime ?? 5 }
}
