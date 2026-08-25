// Visited States Map – SwiftUI + MapKit overlays
// iOS 17+ (SwiftUI, MapKit, SwiftData)

import SwiftUI
import MapKit
import SwiftData
import CoreLocation
import UniformTypeIdentifiers
import PhotosUI
import Photos

// MARK: - Models

@Model
final class VisitedState: Identifiable {
    @Attribute(.unique) var code: String
    @Relationship(deleteRule: .cascade) var visits: [StateVisit] = []
    @Relationship(deleteRule: .cascade) var photos: [StatePhoto] = []
    @Relationship(deleteRule: .cascade) var cities: [VisitedCity] = []
    init(code: String) { self.code = code }
}

@Model
final class VisitedCity {
    var name: String
    var latitude: Double
    var longitude: Double
    init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

@Model
final class StateVisit {
    var startDate: Date?
    var endDate: Date?
    init(startDate: Date? = nil, endDate: Date? = nil) {
        self.startDate = startDate
        self.endDate = endDate
    }
}

@Model
final class StatePhoto {
    @Attribute(.externalStorage) var imageData: Data
    var sortOrder: Int
    init(imageData: Data, sortOrder: Int = 0) {
        self.imageData = imageData
        self.sortOrder = sortOrder
    }
}

@Model
final class BucketListState {
    @Attribute(.unique) var code: String
    var addedDate: Date
    init(code: String) {
        self.code = code
        self.addedDate = Date()
    }
}

struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}


@Observable
final class AppState {
    var selectedTab: Int = 0
    var focusedCity: VisitedCity? = nil
}

struct USState: Identifiable, Hashable {
    let id: String      // USPS code, e.g., "CA"
    let name: String
}

// 50 states + DC (shown on map but not counted toward percentage)
let allUSStates: [USState] = [
    .init(id:"AL", name:"Alabama"), .init(id:"AK", name:"Alaska"), .init(id:"AZ", name:"Arizona"), .init(id:"AR", name:"Arkansas"),
    .init(id:"CA", name:"California"), .init(id:"CO", name:"Colorado"), .init(id:"CT", name:"Connecticut"), .init(id:"DE", name:"Delaware"),
    .init(id:"FL", name:"Florida"), .init(id:"GA", name:"Georgia"), .init(id:"HI", name:"Hawaii"), .init(id:"ID", name:"Idaho"),
    .init(id:"IL", name:"Illinois"), .init(id:"IN", name:"Indiana"), .init(id:"IA", name:"Iowa"), .init(id:"KS", name:"Kansas"),
    .init(id:"KY", name:"Kentucky"), .init(id:"LA", name:"Louisiana"), .init(id:"ME", name:"Maine"), .init(id:"MD", name:"Maryland"),
    .init(id:"MA", name:"Massachusetts"), .init(id:"MI", name:"Michigan"), .init(id:"MN", name:"Minnesota"), .init(id:"MS", name:"Mississippi"),
    .init(id:"MO", name:"Missouri"), .init(id:"MT", name:"Montana"), .init(id:"NE", name:"Nebraska"), .init(id:"NV", name:"Nevada"),
    .init(id:"NH", name:"New Hampshire"), .init(id:"NJ", name:"New Jersey"), .init(id:"NM", name:"New Mexico"), .init(id:"NY", name:"New York"),
    .init(id:"NC", name:"North Carolina"), .init(id:"ND", name:"North Dakota"), .init(id:"OH", name:"Ohio"), .init(id:"OK", name:"Oklahoma"),
    .init(id:"OR", name:"Oregon"), .init(id:"PA", name:"Pennsylvania"), .init(id:"RI", name:"Rhode Island"), .init(id:"SC", name:"South Carolina"),
    .init(id:"SD", name:"South Dakota"), .init(id:"TN", name:"Tennessee"), .init(id:"TX", name:"Texas"), .init(id:"UT", name:"Utah"),
    .init(id:"VT", name:"Vermont"), .init(id:"VA", name:"Virginia"), .init(id:"WA", name:"Washington"), .init(id:"WV", name:"West Virginia"),
    .init(id:"WI", name:"Wisconsin"), .init(id:"WY", name:"Wyoming"), .init(id:"DC", name:"Washington DC")
]

// MARK: - Flight Search Data

let stateMainAirports: [String: String] = [
    "AL": "BHM", "AK": "ANC", "AZ": "PHX", "AR": "LIT",
    "CA": "LAX", "CO": "DEN", "CT": "BDL", "DE": "PHL",
    "FL": "MIA", "GA": "ATL", "HI": "HNL", "ID": "BOI",
    "IL": "ORD", "IN": "IND", "IA": "DSM", "KS": "ICT",
    "KY": "SDF", "LA": "MSY", "ME": "PWM", "MD": "BWI",
    "MA": "BOS", "MI": "DTW", "MN": "MSP", "MS": "JAN",
    "MO": "STL", "MT": "BZN", "NE": "OMA", "NV": "LAS",
    "NH": "MHT", "NJ": "EWR", "NM": "ABQ", "NY": "JFK",
    "NC": "CLT", "ND": "FAR", "OH": "CMH", "OK": "OKC",
    "OR": "PDX", "PA": "PHL", "RI": "PVD", "SC": "CHS",
    "SD": "FSD", "TN": "BNA", "TX": "DFW", "UT": "SLC",
    "VT": "BTV", "VA": "DCA", "WA": "SEA", "WV": "CRW",
    "WI": "MKE", "WY": "CPR", "DC": "DCA"
]

// SerpApi Google Flights models
struct SerpFlightGroup: Identifiable, Codable {
    var id = UUID()
    let flights: [SerpFlightSegment]
    let totalDuration: Int
    let price: Int?
    let airlineLogo: String?
    let layovers: [SerpLayover]?

    private enum CodingKeys: String, CodingKey {
        case flights, totalDuration, price, airlineLogo, layovers
    }
}
struct SerpFlightSegment: Codable {
    struct Airport: Codable {
        let name: String
        let id: String
        let time: String // "YYYY-MM-DD HH:mm"
    }
    let departureAirport: Airport
    let arrivalAirport: Airport
    let duration: Int
    let airline: String
    let airlineLogo: String?
    let flightNumber: String
    let airplane: String?
}
struct SerpLayover: Codable {
    let duration: Int
    let name: String
    let id: String
}
private struct SerpApiFlightsResponse: Codable {
    let bestFlights: [SerpFlightGroup]?
    let otherFlights: [SerpFlightGroup]?
    let error: String?
}

@MainActor
@Observable
final class FlightSearchService {
    var offers: [SerpFlightGroup] = []
    var isLoading = false
    var errorMessage: String? = nil

    func search(from origin: String, to destination: String, on date: Date, apiKey: String) async {
        let o = origin.uppercased().trimmingCharacters(in: .whitespaces)
        let d = destination.uppercased().trimmingCharacters(in: .whitespaces)
        guard !o.isEmpty, !d.isEmpty, o != d, !apiKey.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        offers = []
        defer { isLoading = false }
        do {
            var comps = URLComponents(string: "https://serpapi.com/search.json")!
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            comps.queryItems = [
                URLQueryItem(name: "engine",        value: "google_flights"),
                URLQueryItem(name: "departure_id",  value: o),
                URLQueryItem(name: "arrival_id",    value: d),
                URLQueryItem(name: "outbound_date", value: df.string(from: date)),
                URLQueryItem(name: "currency",      value: "USD"),
                URLQueryItem(name: "type",          value: "2"),   // one-way
                URLQueryItem(name: "adults",        value: "1"),
                URLQueryItem(name: "api_key",       value: apiKey)
            ]
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let resp = try decoder.decode(SerpApiFlightsResponse.self, from: data)
            if let err = resp.error {
                throw NSError(domain: "SerpApi", code: 0, userInfo: [NSLocalizedDescriptionKey: err])
            }
            let all = (resp.bestFlights ?? []) + (resp.otherFlights ?? [])
            offers = all.sorted { ($0.price ?? Int.max) < ($1.price ?? Int.max) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - GeoJSON / Overlays Loader
final class StateShapesLoader: ObservableObject {
    @Published var polygons: [String: [MKPolygon]] = [:]

    func loadIfNeeded() {
        guard polygons.isEmpty else { return }
        if let url = Bundle.main.url(forResource: "us_states", withExtension: "geojson") {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Data(contentsOf: url)
                    let decoder = MKGeoJSONDecoder()
                    let objects = try decoder.decode(data)
                    let newPolygons = self.parseGeoJSON(objects)
                    DispatchQueue.main.async {
                        self.polygons = newPolygons
                    }
                } catch {
                    print("Failed to load GeoJSON: \(error)")
                    self.loadFallback()
                }
            }
            return
        }
        loadFallback()
    }

    private func loadFallback() {
        let coords = [
            CLLocationCoordinate2D(latitude: 25, longitude: -125),
            CLLocationCoordinate2D(latitude: 25, longitude: -66),
            CLLocationCoordinate2D(latitude: 49, longitude: -66),
            CLLocationCoordinate2D(latitude: 49, longitude: -125)
        ]
        let polygon = MKPolygon(coordinates: coords, count: coords.count)
        polygon.title = "USA"
        DispatchQueue.main.async {
            self.polygons = ["USA": [polygon]]
        }
    }

    private func parseGeoJSON(_ objects: [MKGeoJSONObject]) -> [String: [MKPolygon]] {
        var result: [String: [MKPolygon]] = [:]
        for object in objects {
            guard let feature = object as? MKGeoJSONFeature else { continue }
            var code: String? = nil
            if let propsData = feature.properties,
               let json = try? JSONSerialization.jsonObject(with: propsData) as? [String: Any] {
                code = (json["STUSPS"] ?? json["STATE"] ?? json["postal"]) as? String
            }
            guard let stateCode = code?.uppercased(), allUSStates.contains(where: { $0.id == stateCode }) else {
                continue
            }
            var acc: [MKPolygon] = result[stateCode] ?? []
            for geom in feature.geometry {
                if let mp = geom as? MKMultiPolygon {
                    for p in mp.polygons { acc.append(p.titled(stateCode)) }
                } else if let p = geom as? MKPolygon {
                    acc.append(p.titled(stateCode))
                }
            }
            result[stateCode] = acc
        }
        return result
    }
}

private extension MKPolygon {
    func titled(_ title: String) -> MKPolygon { self.title = title; return self }
}

// MARK: - MapView (MKMapView bridge)
struct StatesMapView: UIViewRepresentable {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<VisitedState>(\.code)]) private var visited: [VisitedState]

    @ObservedObject var shapes: StateShapesLoader
    var highlightedCode: String? = nil
    var zoomsOnHighlight: Bool = true
    var focusedCity: VisitedCity? = nil

    var initialRegion: MKCoordinateRegion = {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
                           span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 60))
    }()

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView(frame: .zero)
        view.delegate = context.coordinator
        view.pointOfInterestFilter = .excludingAll
        view.isRotateEnabled = false
        view.mapType = .mutedStandard
        view.setRegion(initialRegion, animated: false)
        shapes.loadIfNeeded()
        context.coordinator.syncOverlays(mapView: view)
        return view
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        shapes.loadIfNeeded()
        let highlightChanged = coord.lastHighlightedCode != highlightedCode
        coord.lastHighlightedCode = highlightedCode
        coord.syncOverlays(mapView: mapView)
        if highlightChanged && zoomsOnHighlight {
            if let code = highlightedCode, let polys = shapes.polygons[code], !polys.isEmpty {
                coord.zoomToState(polys, mapView: mapView)
            } else if highlightedCode == nil {
                mapView.setRegion(initialRegion, animated: true)
            }
        }
        // Focus on a city pin
        let newLat = focusedCity?.latitude
        let newLon = focusedCity?.longitude
        if newLat != coord.lastFocusedLat || newLon != coord.lastFocusedLon {
            coord.lastFocusedLat = newLat
            coord.lastFocusedLon = newLon
            mapView.removeAnnotations(mapView.annotations.filter { $0 is MKPointAnnotation })
            if let city = focusedCity {
                let pin = MKPointAnnotation()
                pin.coordinate = CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude)
                pin.title = city.name
                mapView.addAnnotation(pin)
                mapView.setRegion(MKCoordinateRegion(center: pin.coordinate,
                                                     span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)),
                                  animated: true)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: StatesMapView
        var lastHighlightedCode: String? = nil
        var lastFocusedLat: Double? = nil
        var lastFocusedLon: Double? = nil
        init(_ parent: StatesMapView) { self.parent = parent }

        func syncOverlays(mapView: MKMapView) {
            let existing = mapView.overlays
            if !existing.isEmpty { mapView.removeOverlays(existing) }
            for (_, polys) in parent.shapes.polygons {
                for p in polys where p.pointCount > 0 {
                    mapView.addOverlay(p)
                }
            }
        }

        func zoomToState(_ polygons: [MKPolygon], mapView: MKMapView) {
            var rect = MKMapRect.null
            for poly in polygons { rect = rect.union(poly.boundingMapRect) }
            let padding = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
            mapView.setVisibleMapRect(rect, edgePadding: padding, animated: true)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "city") as? MKMarkerAnnotationView
                       ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "city")
            view.markerTintColor = .systemRed
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: polygon)
                let code = polygon.title ?? nil
                if code == parent.highlightedCode {
                    r.fillColor = UIColor.systemOrange.withAlphaComponent(0.45)
                    r.strokeColor = UIColor.systemOrange.withAlphaComponent(0.9)
                    r.lineWidth = 2
                } else if let code, parent.visited.contains(where: { $0.code == code }) {
                    r.fillColor = UIColor.systemGreen.withAlphaComponent(0.35)
                    r.strokeColor = UIColor.label.withAlphaComponent(0.50)
                    r.lineWidth = 1
                } else {
                    r.fillColor = UIColor.systemGray.withAlphaComponent(0.40)
                    r.strokeColor = UIColor.label.withAlphaComponent(0.50)
                    r.lineWidth = 1
                }
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Legend View
struct MapLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.green.opacity(0.35)).frame(width: 14, height: 14)
            Text("Visited")
            Circle().fill(Color.gray.opacity(0.40)).frame(width: 14, height: 14)
            Text("Not visited")
            Spacer()
        }
        .padding(8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding([.horizontal, .bottom])
    }
}

// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onCapture(nil)
        }
    }
}

// MARK: - Zoomable Image View
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.frame = scrollView.bounds
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            imageView.center = CGPoint(x: scrollView.contentSize.width / 2 + offsetX,
                                       y: scrollView.contentSize.height / 2 + offsetY)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / 3,
                                  height: scrollView.bounds.height / 3)
                let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                scrollView.zoom(to: CGRect(origin: origin, size: size), animated: true)
            }
        }
    }
}

// MARK: - Full-Screen Photo Viewer
struct PhotoViewerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var photo: StatePhoto
    let onDelete: () -> Void

    @State private var replaceItem: [PhotosPickerItem] = []

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let uiImage = UIImage(data: photo.imageData) {
                ZoomableImageView(image: uiImage)
                    .ignoresSafeArea()
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.4))
                        .padding()
                }
                Spacer()
            }
            VStack {
                Spacer()
                HStack {
                    PhotosPicker(
                        selection: $replaceItem,
                        maxSelectionCount: 1,
                        matching: .images
                    ) {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                    Button {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .onChange(of: replaceItem) { _, items in
            Task {
                if let item = items.first,
                   let data = try? await item.loadTransferable(type: Data.self) {
                    photo.imageData = data
                    try? modelContext.save()
                }
                replaceItem = []
            }
        }
    }
}

// MARK: - Visit Row
struct VisitRow: View {
    @Bindable var visit: StateVisit
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Start")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                DatePicker("Start date",
                           selection: Binding(
                               get: { visit.startDate ?? Date() },
                               set: { newDate in
                                   visit.startDate = newDate
                                   visit.endDate = newDate
                               }
                           ),
                           displayedComponents: [.date])
                .labelsHidden()
            }
            HStack {
                Text("End")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                DatePicker("End date",
                           selection: Binding(
                               get: { visit.endDate ?? visit.startDate ?? Date() },
                               set: { visit.endDate = $0 }
                           ),
                           in: (visit.startDate ?? .distantPast)...,
                           displayedComponents: [.date])
                .labelsHidden()
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Photo Cell
struct PhotoCell: View {
    @Bindable var photo: StatePhoto
    let onDelete: () -> Void

    @State private var showFullScreen = false

    var body: some View {
        if let uiImage = UIImage(data: photo.imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { showFullScreen = true }
                .fullScreenCover(isPresented: $showFullScreen) {
                    PhotoViewerView(photo: photo, onDelete: {
                        onDelete()
                        showFullScreen = false
                    })
                }
        }
    }
}

// MARK: - Album Picker
struct AlbumPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: ([PHAsset]) -> Void

    struct AlbumItem: Identifiable {
        let id: String
        let collection: PHAssetCollection
        let count: Int
        let thumbnail: UIImage?
    }

    @State private var albums: [AlbumItem] = []

    var body: some View {
        NavigationStack {
            List(albums) { item in
                Button {
                    let assets = Self.fetchAssets(from: item.collection, limit: 20)
                    onSelect(assets)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Group {
                            if let thumb = item.thumbnail {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.gray.opacity(0.15)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.collection.localizedTitle ?? "Untitled")
                                .foregroundStyle(.primary)
                            Text("\(item.count) photo\(item.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .imageScale(.small)
                    }
                }
            }
            .navigationTitle("Choose Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if albums.isEmpty {
                    ProgressView("Loading albums…")
                }
            }
        }
        .task { await loadAlbums() }
    }

    private func loadAlbums() async {
        // Enumerate collections on a background thread — enumerateObjects is synchronous
        // and was blocking the main thread during the sheet open animation.
        let collections: [(PHAssetCollection, PHFetchResult<PHAsset>)] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let imgOptions = PHFetchOptions()
                imgOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                var seen = Set<String>()
                var result: [(PHAssetCollection, PHFetchResult<PHAsset>)] = []

                func collect(_ col: PHAssetCollection) {
                    guard seen.insert(col.localIdentifier).inserted else { return }
                    let fetch = PHAsset.fetchAssets(in: col, options: imgOptions)
                    guard fetch.count > 0 else { return }
                    result.append((col, fetch))
                }

                for subtype: PHAssetCollectionSubtype in [.smartAlbumUserLibrary, .smartAlbumFavorites,
                                                           .smartAlbumRecentlyAdded, .smartAlbumScreenshots] {
                    PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
                        .enumerateObjects { col, _, _ in collect(col) }
                }
                PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
                    .enumerateObjects { col, _, _ in collect(col) }

                continuation.resume(returning: result)
            }
        }

        // Show album names/counts immediately — no thumbnails yet
        await MainActor.run {
            albums = collections.map { (col, fetch) in
                AlbumItem(id: col.localIdentifier, collection: col, count: fetch.count, thumbnail: nil)
            }
        }

        // Fill in thumbnails one by one as they arrive
        for (col, fetch) in collections {
            guard let first = fetch.firstObject else { continue }
            let itemId = col.localIdentifier
            if let thumb = await loadThumbnail(for: first) {
                await MainActor.run {
                    if let idx = albums.firstIndex(where: { $0.id == itemId }) {
                        let old = albums[idx]
                        albums[idx] = AlbumItem(id: old.id, collection: old.collection,
                                               count: old.count, thumbnail: thumb)
                    }
                }
            }
        }
    }

    private func loadThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .fastFormat
            opts.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(for: asset,
                targetSize: CGSize(width: 112, height: 112),
                contentMode: .aspectFill, options: opts) { img, _ in
                continuation.resume(returning: img)
            }
        }
    }

    static func fetchAssets(from collection: PHAssetCollection, limit: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(in: collection, options: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return Array(assets.shuffled().prefix(limit))
    }
}

// MARK: - City Search Completer
final class CitySearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
    }

    func update(query: String, stateName: String) {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            suggestions = []
            completer.queryFragment = ""
        } else {
            completer.queryFragment = "\(query), \(stateName)"
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = Array(completer.results.prefix(8))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}

// MARK: - Add City Sheet
struct AddCitySheet: View {
    @Environment(\.dismiss) private var dismiss
    let stateName: String
    let onAdd: (String, CLLocationCoordinate2D) -> Void

    @State private var query = ""
    @State private var isResolving = false
    @StateObject private var completer = CitySearchCompleter()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search city in \(stateName)…", text: $query)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, val in
                            completer.update(query: val, stateName: stateName)
                        }
                }

                if !completer.suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(completer.suggestions, id: \.self) { suggestion in
                            Button {
                                Task { await resolve(suggestion) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.title)
                                        .foregroundStyle(.primary)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(isResolving)
                        }
                    }
                }
            }
            .navigationTitle("Add City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isResolving { ProgressView() }
                }
            }
        }
    }

    private func resolve(_ completion: MKLocalSearchCompletion) async {
        isResolving = true
        defer { isResolving = false }
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return }
        let name = item.name ?? completion.title
        onAdd(name, item.placemark.coordinate)
        dismiss()
    }
}

// MARK: - State Detail View
struct StateDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Bindable var visitedState: VisitedState
    let stateName: String
    var statePolygons: [MKPolygon] = []

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showSourceMenu = false
    @State private var showCamera = false
    @State private var showPhotosPicker = false
    @State private var isImporting = false
    @State private var importMessage: String? = nil
    @State private var showImportAlert = false
    @State private var showDeleteAllAlert = false
    @State private var showAlbumPicker = false
    @State private var shareableCollage: ShareableImage? = nil
    @AppStorage("homeStateCode") private var homeStateCode: String = ""
    @State private var showAddCity = false

    private let monthNames = Calendar.current.monthSymbols

    var hasDatedVisits: Bool {
        visitedState.visits.contains { $0.startDate != nil }
    }

    var sortedVisits: [StateVisit] {
        visitedState.visits.sorted {
            ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast)
        }
    }

    var sortedPhotos: [StatePhoto] {
        visitedState.photos.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedCities: [VisitedCity] {
        visitedState.cities.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            Section {
                ForEach(sortedVisits) { visit in
                    VisitRow(visit: visit) { deleteVisit(visit) }
                }
                Button {
                    addVisit()
                } label: {
                    Label("Add Visit", systemImage: "plus")
                }
            } header: {
                let count = visitedState.visits.count
                Text(count == 0 ? "Visits" : "Visits (\(count))")
            }

            Section {
                if sortedCities.isEmpty {
                    Text("No cities added yet.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(sortedCities) { city in
                        Button {
                            openInMaps(city)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.red)
                                Text(city.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .imageScale(.small)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indices in
                        for i in indices { modelContext.delete(sortedCities[i]) }
                        try? modelContext.save()
                    }
                }
            } header: {
                HStack {
                    let count = visitedState.cities.count
                    Text(count == 0 ? "Cities" : "Cities (\(count))")
                    Spacer()
                    Button {
                        showAddCity = true
                    } label: {
                        Image(systemName: "plus.circle.fill").imageScale(.large)
                    }
                }
            }

            Section {
                if sortedPhotos.isEmpty {
                    Text("No photos yet. Tap + to add some.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 24)
                } else {
                    let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(sortedPhotos) { photo in
                            PhotoCell(photo: photo) { deletePhoto(photo) }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            } header: {
                HStack {
                    Text("Photos")
                    Spacer()
                    if !sortedPhotos.isEmpty {
                        Button(role: .destructive) {
                            showDeleteAllAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .imageScale(.large)
                                .foregroundStyle(.red)
                        }
                    }
                    Menu {
                        if hasDatedVisits {
                            Button {
                                Task { await importMatchingPhotos() }
                            } label: {
                                Label("By Date & Location", systemImage: "calendar.badge.plus")
                            }
                        }
                        Button {
                            showAlbumPicker = true
                        } label: {
                            Label("From Album", systemImage: "photo.stack")
                        }
                    } label: {
                        if isImporting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .imageScale(.large)
                        }
                    }
                    .disabled(isImporting)
                    Button {
                        showSourceMenu = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .imageScale(.large)
                    }
                }
            }
        }
        .navigationTitle(stateName)
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Add Photo", isPresented: $showSourceMenu) {
            Button("Photo Library") { showPhotosPicker = true }
            Button("Take Photo") { showCamera = true }
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItems, maxSelectionCount: 20, matching: .images)
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                guard let image, let data = image.jpegData(compressionQuality: 0.8) else { return }
                addPhoto(data: data)
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        addPhoto(data: data)
                    }
                }
                selectedItems = []
            }
        }
        .alert("Delete All Photos", isPresented: $showDeleteAllAlert) {
            Button("Delete All", role: .destructive) { deleteAllPhotos() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all \(visitedState.photos.count) photo\(visitedState.photos.count == 1 ? "" : "s") for \(stateName).")
        }
        .alert("Import Complete", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let msg = importMessage { Text(msg) }
        }
        .sheet(isPresented: $showAddCity) {
            AddCitySheet(stateName: stateName) { name, coord in
                addCity(name: name, coordinate: coord)
            }
        }
        .sheet(isPresented: $showAlbumPicker) {
            AlbumPickerView { assets in
                Task { await importFromAlbum(assets: assets) }
            }
        }
        .sheet(item: $shareableCollage) { item in
            ActivityView(activityItems: [item.image])
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    homeStateCode = homeStateCode == visitedState.code ? "" : visitedState.code
                } label: {
                    Image(systemName: homeStateCode == visitedState.code ? "house.fill" : "house")
                }
            }
            if !sortedPhotos.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if let img = generateCollage() {
                            shareableCollage = ShareableImage(image: img)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func addVisit() {
        let visit = StateVisit(startDate: Date(), endDate: Date())
        visitedState.visits.append(visit)
        try? modelContext.save()
    }

    private func deleteVisit(_ visit: StateVisit) {
        visitedState.visits.removeAll { $0 === visit }
        modelContext.delete(visit)
        try? modelContext.save()
    }

    private func addPhoto(data: Data) {
        let photo = StatePhoto(imageData: data, sortOrder: visitedState.photos.count)
        visitedState.photos.append(photo)
        try? modelContext.save()
    }

    private func deleteAllPhotos() {
        for photo in visitedState.photos { modelContext.delete(photo) }
        visitedState.photos.removeAll()
        try? modelContext.save()
    }

    private func deletePhoto(_ photo: StatePhoto) {
        visitedState.photos.removeAll { $0 === photo }
        modelContext.delete(photo)
        try? modelContext.save()
    }

    private func openInMaps(_ city: VisitedCity) {
        appState.focusedCity = city
        appState.selectedTab = 1
    }

    private func addCity(name: String, coordinate: CLLocationCoordinate2D) {
        let city = VisitedCity(name: name, latitude: coordinate.latitude,
                               longitude: coordinate.longitude)
        visitedState.cities.append(city)
        try? modelContext.save()
    }

    @MainActor
    private func importMatchingPhotos() async {
        isImporting = true
        defer { isImporting = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            importMessage = "Photo library access is required. Please enable it in Settings."
            showImportAlert = true
            return
        }

        // Build date predicates from visit date ranges
        var subpredicates: [NSPredicate] = []
        let cal = Calendar.current
        for visit in visitedState.visits {
            guard let start = visit.startDate else { continue }
            // Make the end bound exclusive: endDate+1 day, or startDate+1 day for single-day visits
            let exclusiveEnd = visit.endDate.flatMap { cal.date(byAdding: .day, value: 1, to: $0) }
                            ?? cal.date(byAdding: .day, value: 1, to: start)
                            ?? start
            subpredicates.append(NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                             start as NSDate, exclusiveEnd as NSDate))
        }

        guard !subpredicates.isEmpty else {
            importMessage = "Add a start date to at least one visit to enable date-based import."
            showImportAlert = true
            return
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard assets.count > 0 else {
            importMessage = "No photos found in your library matching your visit dates."
            showImportAlert = true
            return
        }

        // Pre-build flat CGPaths from the state's MKPolygons (MapKit must be read on main thread)
        let statePaths: [CGPath] = statePolygons.compactMap { polygon in
            guard polygon.pointCount >= 3 else { return nil }
            let pts = polygon.points()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
            for i in 1..<polygon.pointCount {
                path.addLine(to: CGPoint(x: pts[i].x, y: pts[i].y))
            }
            path.closeSubpath()
            return path as CGPath
        }

        // Filter date-matched photos by GPS location against the state boundary
        var qualified: [PHAsset] = []
        var noGPSCount = 0
        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            if statePaths.isEmpty {
                // No polygon data loaded yet — fall back to date-only
                qualified.append(asset)
            } else if let loc = asset.location {
                let mp = MKMapPoint(loc.coordinate)
                let pt = CGPoint(x: mp.x, y: mp.y)
                if statePaths.contains(where: { $0.contains(pt) }) {
                    qualified.append(asset)
                }
                // else: has GPS but outside this state — skip
            } else {
                // No GPS metadata — include by date alone
                qualified.append(asset)
                noGPSCount += 1
            }
        }

        guard !qualified.isEmpty else {
            importMessage = "No photos were found within \(stateName)'s boundaries during your visit dates."
            showImportAlert = true
            return
        }

        // Pick up to 20 randomly from the qualified pool
        let selected: [PHAsset] = qualified.count <= 20
            ? qualified
            : Array(qualified.shuffled().prefix(20))

        var importedInState = 0
        var importedNoGPS = 0
        for asset in selected {
            if let data = await loadImageData(for: asset) {
                addPhoto(data: data)
                if asset.location != nil { importedInState += 1 } else { importedNoGPS += 1 }
            }
        }

        let total = importedInState + importedNoGPS
        var note = ""
        if !statePaths.isEmpty && total > 0 {
            if importedNoGPS == 0 {
                note = " (all location-verified)"
            } else if importedInState > 0 {
                note = " (\(importedInState) in-state, \(importedNoGPS) no GPS)"
            } else {
                note = " (no GPS — date-matched only)"
            }
        }
        importMessage = "Imported \(total) photo\(total == 1 ? "" : "s") from \(qualified.count) candidates\(note)."
        showImportAlert = true
    }

    // MARK: Collage generation

    private func generateCollage() -> UIImage? {
        let images = sortedPhotos.prefix(20).compactMap { UIImage(data: $0.imageData) }
        guard !images.isEmpty else { return nil }
        let side: CGFloat = 1080
        let gap: CGFloat = 4
        let canvas = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            UIColor.black.setFill()
            cgCtx.fill(CGRect(origin: .zero, size: canvas))
            let rects = collageRects(count: images.count, canvas: canvas, gap: gap)
            for (i, rect) in rects.enumerated() where i < images.count {
                collageAspectFill(images[i], into: rect, cgCtx: cgCtx)
            }
            // Bottom gradient
            let gradH = side * 0.44
            let colors = [UIColor.black.withAlphaComponent(0).cgColor,
                          UIColor.black.withAlphaComponent(0.9).cgColor]
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray, locations: [0, 1]) {
                cgCtx.drawLinearGradient(grad,
                                         start: CGPoint(x: 0, y: side - gradH),
                                         end: CGPoint(x: 0, y: side), options: [])
            }
            drawCollageText(cgCtx: cgCtx, width: side, height: side)
        }
    }

    private func collageRects(count n: Int, canvas: CGSize, gap g: CGFloat) -> [CGRect] {
        let w = canvas.width, h = canvas.height
        switch n {
        case 1:
            return [CGRect(origin: .zero, size: canvas)]
        case 2:
            let hw = (w - g) / 2
            return [CGRect(x: 0, y: 0, width: hw, height: h),
                    CGRect(x: hw + g, y: 0, width: hw, height: h)]
        case 3:
            let topH = (h - g) * 0.58, botH = h - topH - g, hw = (w - g) / 2
            return [CGRect(x: 0, y: 0, width: w, height: topH),
                    CGRect(x: 0, y: topH + g, width: hw, height: botH),
                    CGRect(x: hw + g, y: topH + g, width: hw, height: botH)]
        case 4:
            let hw = (w - g) / 2, hh = (h - g) / 2
            return [CGRect(x: 0, y: 0, width: hw, height: hh),
                    CGRect(x: hw + g, y: 0, width: hw, height: hh),
                    CGRect(x: 0, y: hh + g, width: hw, height: hh),
                    CGRect(x: hw + g, y: hh + g, width: hw, height: hh)]
        case 5:
            let lw = w * 0.55, rw = w - lw - g
            let hw = (rw - g) / 2, hh = (h - g) / 2
            return [CGRect(x: 0, y: 0, width: lw, height: h),
                    CGRect(x: lw + g, y: 0, width: hw, height: hh),
                    CGRect(x: lw + g + hw + g, y: 0, width: hw, height: hh),
                    CGRect(x: lw + g, y: hh + g, width: hw, height: hh),
                    CGRect(x: lw + g + hw + g, y: hh + g, width: hw, height: hh)]
        case 6:
            let tw = (w - 2 * g) / 3, hh = (h - g) / 2
            return (0..<6).map { i in
                CGRect(x: CGFloat(i % 3) * (tw + g), y: CGFloat(i / 3) * (hh + g), width: tw, height: hh)
            }
        case 7...9:
            let tw = (w - 2 * g) / 3, th = (h - 2 * g) / 3
            return (0..<n).map { i in
                CGRect(x: CGFloat(i % 3) * (tw + g), y: CGFloat(i / 3) * (th + g), width: tw, height: th)
            }
        default:
            // 10–16 → 4 columns; 17–20 → 5 columns
            let cols = n <= 16 ? 4 : 5
            let rows = (n + cols - 1) / cols
            let cellW = (w - CGFloat(cols - 1) * g) / CGFloat(cols)
            let cellH = (h - CGFloat(rows - 1) * g) / CGFloat(rows)
            let lastRowCount = n % cols == 0 ? cols : n % cols
            return (0..<n).map { i in
                let row = i / cols, col = i % cols
                let y = CGFloat(row) * (cellH + g)
                if row == rows - 1 && lastRowCount < cols {
                    let lw = (w - CGFloat(lastRowCount - 1) * g) / CGFloat(lastRowCount)
                    return CGRect(x: CGFloat(col) * (lw + g), y: y, width: lw, height: cellH)
                }
                return CGRect(x: CGFloat(col) * (cellW + g), y: y, width: cellW, height: cellH)
            }
        }
    }

    private func collageAspectFill(_ image: UIImage, into rect: CGRect, cgCtx: CGContext) {
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let sw = image.size.width * scale, sh = image.size.height * scale
        cgCtx.saveGState()
        cgCtx.clip(to: rect)
        image.draw(in: CGRect(x: rect.minX + (rect.width - sw) / 2,
                              y: rect.minY + (rect.height - sh) / 2,
                              width: sw, height: sh))
        cgCtx.restoreGState()
    }

    private func drawCollageText(cgCtx: CGContext, width w: CGFloat, height h: CGFloat) {
        func centered(_ str: NSAttributedString, y: CGFloat) {
            str.draw(at: CGPoint(x: (w - str.size().width) / 2, y: y))
        }

        var y = h - 54

        let nameStr = NSAttributedString(string: stateName.uppercased(), attributes: [
            .font: UIFont.systemFont(ofSize: 54, weight: .black),
            .foregroundColor: UIColor.white,
            .kern: 4.0
        ])
        y -= nameStr.size().height
        centered(nameStr, y: y)

        y -= 14
        cgCtx.setFillColor(UIColor.white.withAlphaComponent(0.22).cgColor)
        cgCtx.fill(CGRect(x: (w - 48) / 2, y: y, width: 48, height: 1.5))

        let dateText = collageSubtitle()
        if !dateText.isEmpty {
            let dateStr = NSAttributedString(string: dateText.uppercased(), attributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55),
                .kern: 3.0
            ])
            y -= dateStr.size().height + 8
            centered(dateStr, y: y)
        }
    }

    private func collageSubtitle() -> String {
        let dated = sortedVisits.compactMap { v -> (Date, Date?)? in
            guard let s = v.startDate else { return nil }
            return (s, v.endDate)
        }
        guard let (start, end) = dated.first else { return "" }
        let fmt = DateFormatter()
        if let end, !Calendar.current.isDate(start, equalTo: end, toGranularity: .month) {
            fmt.dateFormat = "MMM yyyy"
            return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
        }
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: start)
    }

    @MainActor
    private func importFromAlbum(assets: [PHAsset]) async {
        isImporting = true
        defer { isImporting = false }
        var added = 0
        for asset in assets {
            if let data = await loadImageData(for: asset) {
                addPhoto(data: data)
                added += 1
            }
        }
        importMessage = "Added \(added) photo\(added == 1 ? "" : "s") from the album."
        showImportAlert = true
    }

    private func loadImageData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

// MARK: - Sidebar list with toggles
struct StatesListView: View {
    var onMapTap: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<VisitedState>(\.code)]) private var visited: [VisitedState]
    @State private var search = ""
    @StateObject private var shapes = StateShapesLoader()
    @State private var visitedExpanded = false
    @State private var shareableReport: ShareableImage? = nil
    @AppStorage("homeStateCode") private var homeStateCode: String = ""
    @AppStorage("colorSchemePreference") private var colorSchemeRaw: Int = 0
    @Binding var highlightedCode: String?

    private var appearanceIcon: String {
        switch colorSchemeRaw {
        case 1: return "sun.max.fill"
        case 2: return "moon.fill"
        default: return "circle.lefthalf.filled"
        }
    }

    var filteredStates: [USState] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allUSStates }
        return allUSStates.filter { $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    var visitedStatesList: [USState] {
        let vset = Set(visited.map { $0.code })
        return allUSStates.filter { vset.contains($0.id) }
    }

    var visitedNonDCCount: Int {
        visited.filter { $0.code != "DC" }.count
    }


    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                MapLegend().ignoresSafeArea(edges: .top)
                StatesMapView(shapes: shapes, highlightedCode: highlightedCode)
                    .frame(height: 150)
            }
            .onTapGesture { onMapTap?() }
            List {
                DisclosureGroup(isExpanded: $visitedExpanded) {
                    ForEach(visitedStatesList) { state in
                        row(for: state)
                    }
                } label: {
                    Text("Visited: \(visitedNonDCCount)/50 states. \(visitedNonDCCount*100/50)% of the US")
                }
                Section(header: Text("All States")) {
                    ForEach(filteredStates) { state in
                        row(for: state)
                    }
                }
            }
            .navigationDestination(for: String.self) { code in
                if let vs = visited.first(where: { $0.code == code }),
                   let name = allUSStates.first(where: { $0.id == code })?.name {
                    StateDetailView(visitedState: vs, stateName: name, statePolygons: shapes.polygons[code] ?? [])
                }
            }
            .searchable(text: $search)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: prepareShare) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Appearance", selection: $colorSchemeRaw) {
                            Label("System", systemImage: "circle.lefthalf.filled").tag(0)
                            Label("Light", systemImage: "sun.max").tag(1)
                            Label("Dark", systemImage: "moon").tag(2)
                        }
                    } label: {
                        Image(systemName: appearanceIcon)
                    }
                }
            }
            .sheet(item: $shareableReport) { item in
                ActivityView(activityItems: [item.image])
            }
        }
        .navigationTitle("🇺🇸 USA Visited States")
    }

    @ViewBuilder
    private func row(for state: USState) -> some View {
        let isVisited = visited.contains(where: { $0.code == state.id })
        let entry = visited.first(where: { $0.code == state.id })
        HStack(spacing: 10) {
            stateFlagImage(for: state.id)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.orange, lineWidth: highlightedCode == state.id ? 2.5 : 0)
                )
                .onTapGesture {
                    withAnimation {
                        highlightedCode = highlightedCode == state.id ? nil : state.id
                    }
                }
            if isVisited {
                NavigationLink(value: state.id) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(state.name)
                            if homeStateCode == state.id {
                                Image(systemName: "house.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        visitSubtitle(for: entry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 5) {
                    Text(state.name)
                    if homeStateCode == state.id {
                        Image(systemName: "house.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
            Toggle(isOn: Binding(
                get: { isVisited },
                set: { on in Task { await setVisited(on, code: state.id) } }
            )) { EmptyView() }
                .labelsHidden()
                .fixedSize()
        }
    }

    @ViewBuilder
    private func stateFlagImage(for code: String) -> some View {
        let flagShape = RoundedRectangle(cornerRadius: 3)
        if let uiImage = UIImage(named: code) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 22)
                .clipShape(flagShape)
                .overlay(flagShape.stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
        } else {
            flagShape
                .fill(Color.gray.opacity(0.12))
                .frame(width: 36, height: 22)
                .overlay(flagShape.stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private func visitSubtitle(for entry: VisitedState?) -> some View {
        let count = entry?.visits.count ?? 0
        if count > 0 {
            Text(count == 1 ? "1 visit" : "\(count) visits")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func setVisited(_ on: Bool, code: String) async {
        if on {
            if !visited.contains(where: { $0.code == code }) {
                modelContext.insert(VisitedState(code: code))
                try? modelContext.save()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } else {
            if let obj = visited.first(where: { $0.code == code }) {
                modelContext.delete(obj)
                try? modelContext.save()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func prepareShare() {
        if let img = generateStatesImage() {
            shareableReport = ShareableImage(image: img)
        }
    }

    private func generateStatesImage() -> UIImage? {
        let cols = 6
        let canvasW: CGFloat = 1080
        let hPad: CGFloat = 44
        let cellW = (canvasW - 2 * hPad) / CGFloat(cols)
        let flagW = cellW - 10
        let flagH = flagW * (22.0 / 36.0)
        let nameH: CGFloat = 18
        let cellH = flagH + 6 + nameH + 16

        let visitedList = visitedStatesList
        let visitedCodes = Set(visitedList.map { $0.id })
        let pendingList = allUSStates.filter { !visitedCodes.contains($0.id) }

        let visitedRows = max(1, (visitedList.count + cols - 1) / cols)
        let pendingRows = max(1, (pendingList.count + cols - 1) / cols)

        let titleAreaH: CGFloat = 150
        let sectionHeaderH: CGFloat = 56
        let sectionGap: CGFloat = 36
        let bottomPad: CGFloat = 60

        let totalH = titleAreaH
                     + sectionHeaderH + CGFloat(visitedRows) * cellH
                     + sectionGap
                     + sectionHeaderH + CGFloat(pendingRows) * cellH
                     + bottomPad

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasW, height: totalH))
        return renderer.image { ctx in
            let cg = ctx.cgContext

            UIColor.white.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: canvasW, height: totalH))

            var y: CGFloat = 48

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 46, weight: .bold),
                .foregroundColor: UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)
            ]
            NSAttributedString(string: "States Visited", attributes: titleAttrs)
                .draw(at: CGPoint(x: hPad, y: y))
            y += 58

            let visitedNonDC = visitedList.filter { $0.id != "DC" }.count
            let pct = visitedNonDC == 0 ? 0 : visitedNonDC * 100 / 50
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .regular),
                .foregroundColor: UIColor.systemGray
            ]
            NSAttributedString(string: "\(visitedNonDC) of 50 states visited  ·  \(pct)%",
                               attributes: subAttrs)
                .draw(at: CGPoint(x: hPad, y: y))
            y += 34

            // Divider
            cg.setFillColor(UIColor(red: 0.82, green: 0.82, blue: 0.86, alpha: 1).cgColor)
            cg.fill(CGRect(x: hPad, y: y, width: canvasW - 2 * hPad, height: 1.5))
            y += 20

            func drawGrid(states: [USState], headerText: String, accentColor: UIColor, countText: String) {
                let headerAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                    .foregroundColor: accentColor
                ]
                let countAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                    .foregroundColor: UIColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1)
                ]
                let secStr = NSMutableAttributedString()
                secStr.append(NSAttributedString(string: headerText, attributes: headerAttrs))
                secStr.append(NSAttributedString(string: countText, attributes: countAttrs))
                secStr.draw(at: CGPoint(x: hPad, y: y))
                y += sectionHeaderH

                for (i, state) in states.enumerated() {
                    let col = CGFloat(i % cols)
                    let row = CGFloat(i / cols)
                    let cellX = hPad + col * cellW
                    let cellY = y + row * cellH

                    let flagX = cellX + (cellW - flagW) / 2
                    let flagRect = CGRect(x: flagX, y: cellY, width: flagW, height: flagH)
                    let rounded = UIBezierPath(roundedRect: flagRect, cornerRadius: 5)

                    if let img = UIImage(named: state.id) {
                        cg.saveGState()
                        rounded.addClip()
                        img.draw(in: flagRect)
                        cg.restoreGState()
                        cg.setStrokeColor(UIColor.gray.withAlphaComponent(0.2).cgColor)
                        cg.setLineWidth(1)
                        rounded.stroke()
                    } else {
                        cg.setFillColor(accentColor.withAlphaComponent(0.10).cgColor)
                        rounded.fill()
                        let codeAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                            .foregroundColor: accentColor
                        ]
                        let codeStr = NSAttributedString(string: state.id, attributes: codeAttrs)
                        let sz = codeStr.size()
                        codeStr.draw(at: CGPoint(x: flagRect.midX - sz.width / 2,
                                                 y: flagRect.midY - sz.height / 2))
                    }

                    let nameAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: UIColor(red: 0.35, green: 0.35, blue: 0.4, alpha: 1)
                    ]
                    let nameStr = NSAttributedString(string: state.name, attributes: nameAttrs)
                    let nameW = nameStr.size().width
                    let nameX = max(cellX, min(cellX + cellW - nameW, flagX + (flagW - nameW) / 2))
                    nameStr.draw(at: CGPoint(x: nameX, y: cellY + flagH + 5))
                }

                let rows = max(1, (states.count + cols - 1) / cols)
                y += CGFloat(rows) * cellH
            }

            let nonDCVisited = visitedList.filter { $0.id != "DC" }.count
            let dcVisited = visitedList.contains { $0.id == "DC" }
            let visitedCountText = dcVisited
                ? " (\(nonDCVisited)) and District of Columbia"
                : " (\(nonDCVisited))"
            drawGrid(states: visitedList, headerText: "✓  Visited", accentColor: .systemGreen, countText: visitedCountText)
            y += sectionGap
            drawGrid(states: pendingList, headerText: "○  To Visit", accentColor: .systemGray, countText: " (\(pendingList.count))")
        }
    }
}

// MARK: - Flight Setup
struct FlightSetupView: View {
    @AppStorage("homeAirportCode") private var homeAirport: String = ""
    @AppStorage("serpApiKey") private var serpApiKey: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. JFK, LAX, ORD", text: $homeAirport)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Home Airport (IATA Code)")
                } footer: {
                    Text("Enter the 3-letter code for your nearest airport.")
                }
                Section {
                    SecureField("API Key", text: $serpApiKey)
                        .autocorrectionDisabled()
                } header: {
                    Text("SerpApi Key")
                } footer: {
                    Text("Sign up for a free account at serpapi.com — the free plan includes 250 searches/month. Results come directly from Google Flights.")
                }
            }
            .navigationTitle("Flight Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - State Flights View
struct StateFlightsView: View {
    let state: USState
    @AppStorage("homeAirportCode") private var homeAirport: String = ""
    @AppStorage("serpApiKey") private var serpApiKey: String = ""
    @State private var service = FlightSearchService()
    @State private var selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
    @State private var showCustomDate = false
    @State private var showSetup = false

    private var destinationAirport: String { stateMainAirports[state.id] ?? "" }
    private var isConfigured: Bool { !homeAirport.trimmingCharacters(in: .whitespaces).isEmpty && !serpApiKey.isEmpty }

    private var next7Days: [Date] {
        (1...7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }
    }

    private static let chipFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE\nMMM d"; return f
    }()
    private static let headerFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .none; return f
    }()

    var body: some View {
        Group {
            if !isConfigured {
                ContentUnavailableView {
                    Label("Flight Setup Needed", systemImage: "airplane.departure")
                } description: {
                    Text("Add your home airport and a free SerpApi key to search Google Flights.")
                } actions: {
                    Button("Open Settings") { showSetup = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if destinationAirport.isEmpty {
                ContentUnavailableView("No Airport Data",
                    systemImage: "questionmark.circle",
                    description: Text("No major airport found for \(state.name)."))
            } else {
                flightsBody
            }
        }
        .navigationTitle("Flights to \(state.name)")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showSetup) { FlightSetupView() }
        .task(id: selectedDate) {
            guard isConfigured, !destinationAirport.isEmpty else { return }
            await service.search(from: homeAirport, to: destinationAirport,
                                 on: selectedDate, apiKey: serpApiKey)
        }
        .onChange(of: isConfigured) { _, configured in
            guard configured, !destinationAirport.isEmpty else { return }
            Task { await service.search(from: homeAirport, to: destinationAirport,
                                         on: selectedDate, apiKey: serpApiKey) }
        }
    }

    @ViewBuilder
    private var flightsBody: some View {
        VStack(spacing: 0) {
            // Route + settings bar
            HStack {
                Label("\(homeAirport.uppercased())  →  \(destinationAirport)", systemImage: "airplane")
                    .font(.subheadline.bold())
                Spacer()
                Button { showSetup = true } label: {
                    Image(systemName: "gear").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            // 7-day chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(next7Days, id: \.timeIntervalSinceReferenceDate) { day in
                        let sel = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                        Button { selectedDate = day; showCustomDate = false } label: {
                            Text(Self.chipFormatter.string(from: day))
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(sel ? Color.blue : Color(.tertiarySystemBackground))
                                .foregroundStyle(sel ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    Button { showCustomDate.toggle() } label: {
                        Label("Other date", systemImage: "calendar")
                            .font(.caption2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(showCustomDate ? Color.blue.opacity(0.15) : Color(.tertiarySystemBackground))
                            .foregroundStyle(showCustomDate ? .blue : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            if showCustomDate {
                DatePicker("Select Date", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                    .background(Color(.secondarySystemBackground))
            }

            Divider()

            // Results
            if service.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching \(Self.headerFormatter.string(from: selectedDate))…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = service.errorMessage {
                ContentUnavailableView("Search Failed", systemImage: "wifi.exclamationmark",
                    description: Text(err))
            } else if service.offers.isEmpty {
                ContentUnavailableView("No Flights Found", systemImage: "airplane",
                    description: Text("No flights from \(homeAirport.uppercased()) to \(destinationAirport) on \(Self.headerFormatter.string(from: selectedDate))."))
            } else {
                List(service.offers) { offer in
                    FlightRow(offer: offer,
                              origin: homeAirport,
                              destination: destinationAirport,
                              date: selectedDate)
                }
                .listStyle(.plain)
                .refreshable {
                    await service.search(from: homeAirport, to: destinationAirport,
                                         on: selectedDate, apiKey: serpApiKey)
                }
            }
        }
    }
}

struct FlightRow: View {
    let offer: SerpFlightGroup
    let origin: String
    let destination: String
    let date: Date

    @State private var isExpanded = false

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let srcFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()
    private static let urlDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var bookingURL: URL? {
        let q = "Flights from \(origin.uppercased()) to \(destination.uppercased()) on \(Self.urlDateFmt.string(from: date))"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/travel/flights?q=\(q)")
    }

    var body: some View {
        let first   = offer.flights.first
        let last    = offer.flights.last
        let stops   = max(0, offer.flights.count - 1)
        let airline = first?.airline ?? "?"
        let depart  = first.map { formatTime($0.departureAirport.time) } ?? ""
        let arrive  = last.map  { formatTime($0.arrivalAirport.time)   } ?? ""
        let price   = offer.price.map { "$\($0)" } ?? "—"

        VStack(alignment: .leading, spacing: 0) {
            // Summary header (always visible)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(airline).font(.caption).foregroundStyle(.secondary)
                        Text(stops == 0 ? "Nonstop" : "\(stops) stop\(stops > 1 ? "s" : "")")
                            .font(.caption)
                            .foregroundStyle(stops == 0 ? .green : .orange)
                    }
                    HStack(spacing: 8) {
                        Text(depart).font(.title3.bold())
                        Image(systemName: "arrow.right").imageScale(.small).foregroundStyle(.secondary)
                        Text(arrive).font(.title3.bold())
                    }
                    Text(formatMinutes(offer.totalDuration)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(price).font(.title2.bold()).foregroundStyle(.blue)
                    Text("per person").font(.caption2).foregroundStyle(.secondary)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)

            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().padding(.bottom, 10)

                    ForEach(0..<offer.flights.count, id: \.self) { idx in
                        let seg = offer.flights[idx]
                        segmentRow(seg)
                        if idx < offer.flights.count - 1 {
                            let layover = offer.layovers.flatMap { $0.count > idx ? $0[idx] : nil }
                            layoverRow(layover, fallbackCode: seg.arrivalAirport.id)
                        }
                    }

                    if let url = bookingURL {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            HStack {
                                Image(systemName: "airplane.departure")
                                Text("Book on Google Flights")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    }
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let url = bookingURL {
                Button { UIApplication.shared.open(url) } label: {
                    Label("Book", systemImage: "airplane.departure")
                }
                .tint(.blue)
            }
        }
    }

    @ViewBuilder
    private func segmentRow(_ seg: SerpFlightSegment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(formatTime(seg.departureAirport.time))
                    .font(.subheadline.bold())
                    .frame(width: 72, alignment: .trailing)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(seg.departureAirport.id)  ·  \(seg.departureAirport.name)")
                        .font(.subheadline).lineLimit(1)
                    Text([seg.airline, seg.flightNumber, seg.airplane]
                            .compactMap { $0 }.joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Text(formatTime(seg.arrivalAirport.time))
                    .font(.subheadline.bold())
                    .frame(width: 72, alignment: .trailing)
                Text("\(seg.arrivalAirport.id)  ·  \(seg.arrivalAirport.name)")
                    .font(.subheadline).lineLimit(1)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func layoverRow(_ layover: SerpLayover?, fallbackCode: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock").imageScale(.small).foregroundStyle(.orange)
            if let lv = layover {
                Text("\(formatMinutes(lv.duration)) layover  ·  \(lv.name) (\(lv.id))")
            } else {
                Text("Connection at \(fallbackCode)")
            }
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(.leading, 82)
        .padding(.bottom, 10)
    }

    private func formatTime(_ s: String) -> String {
        if let d = Self.srcFmt.date(from: s) { return Self.timeFmt.string(from: d) }
        return String(s.suffix(5))
    }

    private func formatMinutes(_ mins: Int) -> String {
        let h = mins / 60, m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Bucket List
struct BucketListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<BucketListState>(\.addedDate)]) private var bucketList: [BucketListState]
    @Query(sort: [SortDescriptor<VisitedState>(\.code)]) private var visited: [VisitedState]
    @State private var search = ""
    @State private var showFlightSetup = false

    private var visitedCodes: Set<String> { Set(visited.map { $0.code }) }
    private var bucketCodes: Set<String> { Set(bucketList.map { $0.code }) }

    private var bucketStates: [USState] {
        bucketList.compactMap { bl in allUSStates.first { $0.id == bl.code } }
    }

    private var availableStates: [USState] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allUSStates
            .filter { !bucketCodes.contains($0.id) && !visitedCodes.contains($0.id) }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    var body: some View {
        List {
            Section {
                if bucketList.isEmpty {
                    Label("Add states you'd like to visit from the list below.", systemImage: "star.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(bucketStates) { state in
                        NavigationLink(destination: StateFlightsView(state: state)) {
                            HStack(spacing: 10) {
                                flagImage(for: state.id)
                                Text(state.name)
                                Spacer()
                                Image(systemName: "airplane")
                                    .foregroundStyle(.blue.opacity(0.7))
                                    .font(.subheadline)
                            }
                        }
                    }
                    .onDelete { indices in
                        for i in indices {
                            let code = bucketStates[i].id
                            if let obj = bucketList.first(where: { $0.code == code }) {
                                modelContext.delete(obj)
                            }
                        }
                        try? modelContext.save()
                    }
                }
            } header: {
                Text(bucketList.isEmpty ? "My Bucket List" : "My Bucket List (\(bucketList.count))")
            }

            Section("Add States") {
                if availableStates.isEmpty && search.isEmpty {
                    Text("All available states are on your bucket list.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else if availableStates.isEmpty {
                    Text("No states match \"\(search)\"")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(availableStates) { state in
                        Button { add(code: state.id) } label: {
                            HStack(spacing: 10) {
                                flagImage(for: state.id)
                                Text(state.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search states to add")
        .navigationTitle("Bucket List")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showFlightSetup = true } label: {
                    Image(systemName: "airplane.departure")
                }
            }
            if !bucketList.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showFlightSetup) { FlightSetupView() }
    }

    private func add(code: String) {
        guard !bucketCodes.contains(code) else { return }
        modelContext.insert(BucketListState(code: code))
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @ViewBuilder
    private func flagImage(for code: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        if let uiImage = UIImage(named: code) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 22)
                .clipShape(shape)
                .overlay(shape.stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
        } else {
            shape
                .fill(Color.gray.opacity(0.12))
                .frame(width: 36, height: 22)
                .overlay(shape.stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
        }
    }
}

// UIKit wrapper for UIActivityViewController
struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Main Content with Tabs
struct ContentView: View {
    @State private var appState = AppState()
    @State private var highlightedCode: String? = nil
    @AppStorage("colorSchemePreference") private var colorSchemeRaw: Int = 0

    private var preferredScheme: ColorScheme? {
        switch colorSchemeRaw {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some View {
        TabView(selection: Binding(get: { appState.selectedTab },
                                  set: { appState.selectedTab = $0 })) {
            NavigationStack {
                StatesListView(onMapTap: { appState.selectedTab = 1 }, highlightedCode: $highlightedCode)
            }
            .tabItem {
                Label("States", systemImage: "list.bullet")
            }
            .tag(0)

            NavigationStack {
                ZStack(alignment: .bottomLeading) {
                    StatesMapView(shapes: StateShapesLoader(),
                                 highlightedCode: highlightedCode,
                                 zoomsOnHighlight: false,
                                 focusedCity: appState.focusedCity)
                    MapLegend()
                }
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }
            .tag(1)

            NavigationStack {
                BucketListView()
            }
            .tabItem {
                Label("Bucket List", systemImage: "star.circle")
            }
            .tag(2)
        }
        .environment(appState)
        .preferredColorScheme(preferredScheme)
    }
}

// MARK: - App entry
@main
struct VisitedStatesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [VisitedState.self, StateVisit.self, StatePhoto.self, VisitedCity.self, BucketListState.self])
    }
}
