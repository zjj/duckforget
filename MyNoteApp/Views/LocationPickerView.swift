import SwiftUI
import MapKit
import CoreLocation

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    
    // Default to San Francisco, but attempt to get current location
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedLocationName: String = "Selected Location"
    
    let onSelect: (CLLocationCoordinate2D, UIImage) -> Void
    
    // Map Snapshotter
    @State private var snapshotter: MKMapSnapshotter?

    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    Map(position: $position) {
                        if let coordinate = selectedCoordinate {
                            Marker(selectedLocationName, coordinate: coordinate)
                        }
                    }
                    .onTapGesture { screenCoord in
                        if let location = proxy.convert(screenCoord, from: .local) {
                            selectedCoordinate = location
                            reverseGeocode(location: location)
                        }
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                        MapScaleView()
                    }
                }
                
                VStack {
                    Spacer()
                    if selectedCoordinate != nil {
                        Button {
                            confirmSelection()
                        } label: {
                            Text("发送位置")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(theme.colors.accent)
                                .cornerRadius(12)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("选择位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Request location access if needed
                CLLocationManager().requestWhenInUseAuthorization()
            }
        }
    }
    
    private func reverseGeocode(location: CLLocationCoordinate2D) {
        Task {
            let searchRequest = MKLocalSearch.Request()
            searchRequest.region = MKCoordinateRegion(center: location, latitudinalMeters: 100, longitudinalMeters: 100)
            searchRequest.resultTypes = .pointOfInterest
            
            let search = MKLocalSearch(request: searchRequest)
            if let response = try? await search.start(),
               let item = response.mapItems.first {
                selectedLocationName = item.name ?? "Selected Location"
            } else {
                // Format as coordinates if no POI found nearby
                selectedLocationName = String(format: "%.4f, %.4f", location.latitude, location.longitude)
            }
        }
    }
    
    private func confirmSelection() {
        guard let coordinate = selectedCoordinate else { return }
        
        // Generate snapshot
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        options.size = CGSize(width: 300, height: 300)
        options.scale = 3.0 // Use a fixed scale appropriate for modern devices
        
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            guard let snapshot = snapshot else {
                // Fallback if snapshot fails (less likely)
                dismiss()
                return
            }
            
            // Draw marker on snapshot
            let image = UIGraphicsImageRenderer(size: options.size).image { _ in
                snapshot.image.draw(at: .zero)
                
                let pinImage = UIImage(systemName: "mappin.circle.fill") ?? UIImage()
                let pinCenter = snapshot.point(for: coordinate)
                let pinSize = CGSize(width: 40, height: 40)
                                
                // Draw pin centered on the coordinate
                let pinRect = CGRect(
                    x: pinCenter.x - pinSize.width / 2,
                    y: pinCenter.y - pinSize.height / 2,
                    width: pinSize.width,
                    height: pinSize.height
                )
                
                // Set color to red/accent
                let config = UIImage.SymbolConfiguration(paletteColors: [.red, .white])
                let configuredPin = pinImage.applyingSymbolConfiguration(config) ?? pinImage
                configuredPin.draw(in: pinRect)
            }
            
            onSelect(coordinate, image)
            dismiss()
        }
    }
}
