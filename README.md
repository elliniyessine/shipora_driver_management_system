# Shipora Driver Management System
This a proof of concept for the Driver Management System web service, which is a part of the Shipora Urban IT planning project.
It is written in Swift, uses the Vapor framework and MongoDB.

## Exposed API endpoints:
- `POST /api/delivery-request/create`: creates a new delivery request.
- `GET  /api/delivery/:id`: returns the delivery request that has the given id.
- `POST /api/delivery/dispatch`: assigns a driver to the delivery request.
#### Example usage:
```bash
# Create a new delivery request
curl -X POST http://localhost:8080/api/delivery-request/create -H "Content-Type: application/json" -d '{"deliveryId":"d210","orderId":"o203","pickupLocation":{"lat":36.8425,"lng":10.2430,"address":"Lac 1"},"dropoffLocation":{"lat":36.8533,"lng":10.2715,"address":"Lac 2"},"route":[{"lat":36.8425,"lng":10.2430},{"lat":36.8460,"lng":10.2540},{"lat":36.8533,"lng":10.2715}]}'

# Check that the delivery request was created, and verify that its status is pending
curl http://localhost:8080/api/delivery/d210

# Assign a driver to the delivery request
curl -X POST http://localhost:8080/api/delivery/dispatch -H "Content-Type: application/json" -d '{"deliveryId":"d210","driverId":403, "driverNotes": "Ezreb rou7ek"}'

# Verify that the delivery's driver, status and driverNotes were added / updated
curl http://localhost:8080/api/delivery/d210
```

## Getting Started
To run the web service locally, you'll need to install Swift, Vapor and libmongoc (the last one is needed on Linux only)

Then you can execute `swift run` in the root directory of the repo.

You also need to run MongoDB and set the `MONGODB_URI` environment variable. If its unset, MongoDB is expected on localhost:27017

## License
This project is licensed under the terms of the Affero General Public License, version 3 or later. For more details, see [COPYING](./COPYING).
