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
                            Annotation(selectedLocationName, coordinate: coordinate) {
                                LocationMarkerBadge(
                                    title: selectedLocationName,
                                    noteCount: 1,
                                    isSelected: true,
                                    accentColor: theme.colors.accent
                                )
                            }
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
                selectedLocationName = item.name ?? "标记位置"
            } else {
                selectedLocationName = "标记位置"
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
            let image = LocationSnapshotRenderer.render(
                snapshot: snapshot,
                coordinate: coordinate,
                title: selectedLocationName,
                accentColor: UIColor(theme.colors.accent)
            )
            
            onSelect(coordinate, image)
            dismiss()
        }
    }
}
