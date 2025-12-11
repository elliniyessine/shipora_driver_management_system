// SPDX-License-Identifier: AGPL-3.0-or-later

import MongoDBVapor
import Vapor

/// A type matching the structure of documents in the corresponding MongoDB collection.
struct DeliveryRequest: Content {
    let _id: BSONObjectID?
    let deliveryId: String
    let orderId: String
    let driverId: Int? //This is optional because when creating a delivery request, it doesn't have a driver yet
    let pickupLocation: Location
    let dropoffLocation: Location
    let route: [Location]
    // The following three properties are optional because they get their values while prosessing the create delivery POST i.e. we don't expect them in the POST's payload
    let status: DeliveryStatus?
    var createdAt: Date?
    var updatedAt: Date?
    let driverNotes: String?
}

struct DispatchDeliveryRequest: Content {
    let deliveryId: String
    let driverId: Int
    let driverNotes: String?
}

struct Location: Content {
    let lat: Double
    let lng: Double
    let address: String?
}

enum DeliveryStatus: String, Content {
    case pending = "pending"            // No driver assigned yet
    case dispatched = "dispatched"      // Driver assigned, ready to pick up
    case pickedUp = "picked_up"         // Driver collected package from warehouse
    case inTransit = "in_transit"       // Driver en route to customer
    case delivered = "delivered"        // Successfully delivered to customer
    case failed = "failed_delivery"     // Delivery attempt failed
    case cancelled = "cancelled"        // Delivery cancelled
}

extension Request {
    /// Convenience accessor for the delivery_db.delivery_requests collection.
    var deliveryRequestCollection: MongoCollection<DeliveryRequest> {
        self.application.mongoDB.client.db("delivery_db").collection("delivery_requests", withType: DeliveryRequest.self)
    }
}

func routes(_ app: Application) throws {

    // GET /api/delivery/:id
    // Retrieves a delivery request by its delivery id
    app.get("api", "delivery", ":id") { req async throws -> DeliveryRequest in
        //TODO: try replacing these three lines with let deliveryId = try req.parameters.require("id")
        guard let deliveryId = req.parameters.get("id"),
              !deliveryId.isEmpty else {
            throw Abort(.badRequest, reason: "deliveryId parameter is required")
        }
        
        guard let deliveryRequest = try await req.deliveryRequestCollection.findOne([
            "deliveryId": .string(deliveryId)
        ]) else {
            throw Abort(.notFound, reason: "Delivery request not found with deliveryId: '\(deliveryId)'")
        }

        // If the closure return type is `Response` instead of `DeliveryRequest`, you can use these two lines
        //let responseBody = try JSONEncoder().encode(deliveryRequest)
        //return Response(status: .ok, body: .init(data: responseBody))

        return deliveryRequest
    }
    /*
    //GET /api/delivery/:id
    app.get("api", "delivery", ":id") { req async throws -> UserResponse in
        let deliveryID = try req.parameters.require("id")
        let message = "Hello, \(deliveryID)"
        return UserResponse(message: message)
    }
    */

    // POST /api/delivery-request/create
    // Creates a new delivery request with status "dispatched"
    // curl -X POST http://localhost:8080/api/delivery-request/create -H "Content-Type: application/json" -d '{"deliveryId":"d202","orderId":"o203","status":"dispatched","pickupLocation":{"lat":36.8425,"lng":10.2430,"address":"Lac 1"},"dropoffLocation":{"lat":36.8533,"lng":10.2715,"address":"Lac 2"},"route":[{"lat":36.8425,"lng":10.2430,"address":null},{"lat":36.8460,"lng":10.2540,"address":null},{"lat":36.8533,"lng":10.2715,"address":null}]}'
    app.post("api", "delivery-request", "create") { req async throws -> Response in
        let createRequest = try req.content.decode(DeliveryRequest.self)
        
        // Validate required fields
        //TODO: are there more required fields? (check Habib's document)
        guard !createRequest.deliveryId.isEmpty,
              !createRequest.orderId.isEmpty,
              !createRequest.route.isEmpty else {
            throw Abort(.badRequest, reason: "Missing required fields: deliveryId, orderId, and route are required")
        }
        
        let now = Date()
        
        // Create the delivery request document
        let deliveryRequest = DeliveryRequest(
            _id: nil, // Will be auto-generated
            deliveryId: createRequest.deliveryId,
            orderId: createRequest.orderId,
            driverId: nil, // No driver assigned yet
            pickupLocation: createRequest.pickupLocation,
            dropoffLocation: createRequest.dropoffLocation,
            route: createRequest.route,
            status: .pending,
            createdAt: now,
            updatedAt: now,
            driverNotes: createRequest.driverNotes
        )
        
        //TODO: should the deliveryId be provided in the POST in the first place?? shouldn't it be an autoincrement or something?
        // Check if deliveryId already exists
        let existingRequest = try await req.deliveryRequestCollection.findOne([
            "deliveryId": .string(createRequest.deliveryId)
        ])
        
        guard existingRequest == nil else {
            throw Abort(.conflict, reason: "Delivery request with ID '\(createRequest.deliveryId)' already exists")
        }
        
        // Insert into database
        try await req.deliveryRequestCollection.insertOne(deliveryRequest)
        
        // Return success response
        let responseBody = try JSONEncoder().encode([
            "success": String(true),
            "message": "Delivery request created successfully",
            "deliveryId": createRequest.deliveryId,
            "status": DeliveryStatus.pending.rawValue,
        ])
        
        return Response(status: .created, body: .init(data: responseBody))
    }


    // POST /api/delivery/dispatch
    // Dispatches a driver to an existing delivery request
    // Make sure to use a deliveryId that corresponds to a "pending" status, otherwise create a new delivery using POST http://localhost:8080/api/delivery-request/create
    // curl -X POST http://localhost:8080/api/delivery/dispatch -H "Content-Type: application/json" -d '{"deliveryId":"d210","driverId":403, "driverNotes": "Ezreb rou7ek"}'
    app.post("api", "delivery", "dispatch") { req async throws -> Response in
        let dispatchRequest = try req.content.decode(DispatchDeliveryRequest.self)
        
        // Validate required fields
        guard !dispatchRequest.deliveryId.isEmpty,
              dispatchRequest.driverId > 0 else {
            throw Abort(.badRequest, reason: "Missing required fields: deliveryId and driverId are required")
        }
        
        // Find the delivery request by deliveryId
        guard let existingRequest = try await req.deliveryRequestCollection.findOne([
            "deliveryId": .string(dispatchRequest.deliveryId)
        ]) else {
            throw Abort(.notFound, reason: "Delivery request not found with deliveryId: '\(dispatchRequest.deliveryId)'")
        }
        
        // Check if already dispatched
        guard existingRequest.status == .pending else {
            throw Abort(.conflict, reason: "Delivery request '\(dispatchRequest.deliveryId)' is not pending for dispatching to a driver")
        }
        
        let now = Date()
        
        // Prepare update document
        var setDocument: BSONDocument = [
            "driverId": .int64(Int64(dispatchRequest.driverId)),
            "status": .string(DeliveryStatus.dispatched.rawValue),
            "updatedAt": .datetime(now)
        ]
        
        // Add driverNotes if provided
        if let driverNotes = dispatchRequest.driverNotes, !driverNotes.isEmpty {
            setDocument["driverNotes"] = .string(driverNotes)
        }
        
        let updateDoc: BSONDocument = [
            "$set": .document(setDocument)
        ]

        guard let updateResult = try await req.deliveryRequestCollection.updateOne(
            filter: ["deliveryId": .string(dispatchRequest.deliveryId)],
            update: updateDoc
        ) else {
            throw Abort(.internalServerError, reason: "Failed to update delivery request")
        }
        
        //TODO: remove this since we already handle it? the above is internal server error, this one is notFound
        guard updateResult.matchedCount == 1 else {
            throw Abort(.notFound, reason: "Failed to update delivery request")
        }
       
        let isoFormatter = ISO8601DateFormatter()
        // Return success response
        let responseBody = try JSONEncoder().encode([
            "success": String(true),
            "message": "Driver \(dispatchRequest.driverId) dispatched to delivery '\(dispatchRequest.deliveryId)'",
            "deliveryId": dispatchRequest.deliveryId,
            "driverId": String(dispatchRequest.driverId),
            "status": "dispatched",
            "updatedAt": isoFormatter.string(from: now),
        ])
        
        return Response(status: .ok, body: .init(data: responseBody))
    }
}
