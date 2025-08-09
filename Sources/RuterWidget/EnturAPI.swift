import Foundation

struct EnturAPI {
    static let baseURL = "https://api.entur.io/journey-planner/v3/graphql"
    
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
            let expectedDepartureTime: String
            let destinationDisplay: DestinationDisplay
            let serviceJourney: ServiceJourney
            
            struct DestinationDisplay: Codable {
                let frontText: String
            }
            
            struct ServiceJourney: Codable {
                let line: Line
                
                struct Line: Codable {
                    let publicCode: String
                    let transportMode: String
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
                            transportMode
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
            guard let departureDate = ISO8601DateFormatter().date(from: call.expectedDepartureTime) else {
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
}

struct Departure {
    let line: String
    let destination: String
    let departureTime: Date
    let transportMode: String
    let stopName: String
    
    var transportEmoji: String {
        switch transportMode.lowercased() {
        case "bus":
            return "🚌"
        case "tram":
            return "🚋"
        case "metro":
            return "🚇"
        case "train":
            return "🚆"
        default:
            return "🚌"
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
