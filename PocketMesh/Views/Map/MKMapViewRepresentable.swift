import MapKit
import os
import SwiftUI
import PocketMeshServices

private let logger = Logger(subsystem: "com.pocketmesh", category: "MapRepresentable")

/// Representable wrapper for MKMapView with custom contact annotations
struct MKMapViewRepresentable {
    let contacts: [ContactDTO]
    let mapType: MKMapType
    let showLabels: Bool
    let showsUserLocation: Bool

    @Binding var selectedContact: ContactDTO?
    @Binding var cameraRegion: MKCoordinateRegion?

    // Callbacks for callout actions
    let onDetailTap: (ContactDTO) -> Void
    let onMessageTap: (ContactDTO) -> Void
    /// Called once with a closure that returns snapshot parameters from the actual MKMapView (bypasses async binding)
    var onSnapshotParamsGetter: ((@escaping () -> (camera: MKMapCamera, size: CGSize)?) -> Void)?

    @MainActor func _createView(coordinator: Coordinator) -> MKMapView {
        let mapView = coordinator.mapView

        mapView.delegate = coordinator
        mapView.showsUserLocation = showsUserLocation

        // Register annotation views
        mapView.register(
            ContactPinView.self,
            forAnnotationViewWithReuseIdentifier: ContactPinView.reuseIdentifier
        )
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )

        // Provide closure to get snapshot params directly from MKMapView (bypasses async binding lag)
        onSnapshotParamsGetter? { [weak mapView] in
            guard let mapView else { return nil }
            // swiftlint:disable:next force_cast
            return (camera: mapView.camera.copy() as! MKMapCamera, size: mapView.bounds.size)
        }

        return mapView
    }

    @MainActor func _updateView(_ mapView: MKMapView, coordinator: Coordinator) {

        // Update binding setters each render cycle
        coordinator.setSelectedContact = { selectedContact = $0 }
        coordinator.setCameraRegion = { cameraRegion = $0 }
        coordinator.onDetailTap = onDetailTap
        coordinator.onMessageTap = onMessageTap
        coordinator.showLabels = showLabels

        // Mark as programmatic update to prevent feedback loops
        coordinator.isUpdatingFromSwiftUI = true
        defer { coordinator.isUpdatingFromSwiftUI = false }

        // Update map type
        mapView.mapType = mapType

        // Update user location visibility
        mapView.showsUserLocation = showsUserLocation

        // Update annotations
        updateAnnotations(in: mapView, coordinator: coordinator)

        // Update selection state
        updateSelection(in: mapView, coordinator: coordinator)

        // Update region if changed programmatically
        if let region = cameraRegion {
            // Check if binding has caught up with pending user gesture
            if let pendingGesture = coordinator.pendingUserGestureRegion {
                if region.isApproximatelyEqual(to: pendingGesture) {
                    // Binding now reflects user gesture, clear pending state
                    logger.debug("Region: binding caught up, clearing pendingUserGestureRegion")
                    coordinator.pendingUserGestureRegion = nil
                } else {
                    // Binding is stale (hasn't caught up with user gesture), skip applying
                    logger.debug("Region: binding stale (span=\(region.span.latitudeDelta, format: .fixed(precision: 4))), pending span=\(pendingGesture.span.latitudeDelta, format: .fixed(precision: 4))), skipping")
                    return
                }
            }

            let shouldUpdate = coordinator.lastAppliedRegion == nil ||
                !coordinator.lastAppliedRegion!.isApproximatelyEqual(to: region)

            if shouldUpdate {
                logger.debug("Region: applying via setRegion (span=\(region.span.latitudeDelta, format: .fixed(precision: 4)))")
                coordinator.hasPendingProgrammaticRegion = true
                coordinator.hasAppliedInitialRegion = true
                mapView.setRegion(region, animated: coordinator.lastAppliedRegion != nil)
                coordinator.lastAppliedRegion = region
            }
        }
    }

    @MainActor func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Annotation Management

    @MainActor private func updateAnnotations(in mapView: MKMapView, coordinator: Coordinator) {
        let currentAnnotations = mapView.annotations.compactMap { $0 as? ContactAnnotation }
        let currentIDs = Set(currentAnnotations.map { $0.contact.id })
        let newIDs = Set(contacts.map { $0.id })

        // Remove annotations that are no longer in the list
        let toRemove = currentAnnotations.filter { !newIDs.contains($0.contact.id) }
        mapView.removeAnnotations(toRemove)

        // Add new annotations
        let existingIDs = currentIDs.subtracting(Set(toRemove.map { $0.contact.id }))
        let toAdd = contacts.filter { !existingIDs.contains($0.id) }
            .map { ContactAnnotation(contact: $0) }
        mapView.addAnnotations(toAdd)

        // Only update name labels if showLabels or selection actually changed
        // Iterating and calling view(for:) on every update interferes with MKMapView clustering
        let selectedID = selectedContact?.id
        let labelsChanged = showLabels != coordinator.lastShowLabels
        let selectionChanged = selectedID != coordinator.lastSelectedContactID

        if labelsChanged || selectionChanged {
            for annotation in mapView.annotations.compactMap({ $0 as? ContactAnnotation }) {
                if let view = mapView.view(for: annotation) as? ContactPinView {
                    view.showsNameLabel = showLabels && selectedID != annotation.contact.id
                }
            }
            coordinator.lastShowLabels = showLabels
            coordinator.lastSelectedContactID = selectedID
        }
    }

    @MainActor private func updateSelection(in mapView: MKMapView, coordinator: Coordinator) {
        let currentlySelectedAnnotation = mapView.selectedAnnotations.first as? ContactAnnotation

        if let selectedContact {
            // Find the annotation for this contact
            guard let annotation = mapView.annotations
                .compactMap({ $0 as? ContactAnnotation })
                .first(where: { $0.contact.id == selectedContact.id }) else {
                return
            }

            // Only select if not already selected
            if currentlySelectedAnnotation?.contact.id != selectedContact.id {
                mapView.selectAnnotation(annotation, animated: true)
            }
        } else if let current = currentlySelectedAnnotation {
            // Deselect all
            mapView.deselectAnnotation(current, animated: true)
        }
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, MKMapViewDelegate {
        // Binding setters for deferred updates
        var setSelectedContact: ((ContactDTO?) -> Void)?
        var setCameraRegion: ((MKCoordinateRegion?) -> Void)?

        // Callbacks
        var onDetailTap: ((ContactDTO) -> Void)?
        var onMessageTap: ((ContactDTO) -> Void)?

        // Configuration
        var showLabels: Bool = true

        // State management
        var isUpdatingFromSwiftUI = false
        var lastAppliedRegion: MKCoordinateRegion?
        var hasPendingProgrammaticRegion = false
        var hasAppliedInitialRegion = false

        /// Tracks pending user gesture region awaiting async binding sync.
        /// When set, the binding is considered stale until it matches this value.
        var pendingUserGestureRegion: MKCoordinateRegion?

        /// Timestamp of the last cluster tap handled by the gesture recognizer.
        /// Used to prevent double-handling when both gesture and delegate fire.
        var lastClusterTapTime: Date?

        /// Set before showAnnotations calls to ensure pendingUserGestureRegion is set
        /// even if hasPendingProgrammaticRegion is true from a prior setRegion.
        var hasPendingShowAnnotations = false

        // Previous state for change detection (avoid unnecessary view updates that interfere with clustering)
        var lastShowLabels: Bool = true
        var lastSelectedContactID: UUID?

        // Lazily created map view owned by coordinator
        lazy var mapView: MKMapView = {
            let map = MKMapView()
            return map
        }()

        // MARK: - Cluster Tap Handler

        private func handleClusterTap(view: Any?) {
            guard let clusterView = (view as? MKAnnotationView),
                  let cluster = clusterView.annotation as? MKClusterAnnotation else {
                return
            }
            // Mark that we handled this tap to prevent delegate double-handling
            lastClusterTapTime = Date()
            // Mark that we're about to call showAnnotations so regionDidChangeAnimated
            // will set pendingUserGestureRegion to protect against stale binding values
            hasPendingShowAnnotations = true
            logger.debug("Cluster: gesture tapped, calling showAnnotations for \(cluster.memberAnnotations.count) members")
            mapView.showAnnotations(cluster.memberAnnotations, animated: true)
        }

        #if canImport(UIKit)
        @objc func clusterTapped(_ gesture: UITapGestureRecognizer) {
            handleClusterTap(view: gesture.view)
        }
        #else
        @objc func clusterTapped(_ gesture: NSClickGestureRecognizer) {
            handleClusterTap(view: gesture.view)
        }
        #endif

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            // Don't provide custom view for user location
            if annotation is MKUserLocation {
                return nil
            }

            // Handle cluster annotations
            if annotation is MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: annotation
                ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
                    annotation: annotation,
                    reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
                )
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "person.2.fill")
                view.displayPriority = .defaultHigh
                view.canShowCallout = false

                // Remove existing tap gestures to avoid duplicates on reuse
                #if canImport(UIKit)
                view.gestureRecognizers?.filter { $0 is UITapGestureRecognizer }.forEach {
                    view.removeGestureRecognizer($0)
                }
                #else
                (view.gestureRecognizers as [NSGestureRecognizer]).filter { $0 is NSClickGestureRecognizer }.forEach {
                    view.removeGestureRecognizer($0)
                }
                #endif

                // Add tap/click gesture for immediate response (bypasses delegate selection delay)
                #if canImport(UIKit)
                let tap = UITapGestureRecognizer(target: self, action: #selector(clusterTapped(_:)))
                #else
                let tap = NSClickGestureRecognizer(target: self, action: #selector(clusterTapped(_:)))
                #endif
                view.addGestureRecognizer(tap)

                return view
            }

            // Handle contact annotations
            guard let contactAnnotation = annotation as? ContactAnnotation else {
                return nil
            }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: ContactPinView.reuseIdentifier,
                for: annotation
            ) as? ContactPinView ?? ContactPinView(
                annotation: annotation,
                reuseIdentifier: ContactPinView.reuseIdentifier
            )

            view.annotation = annotation
            view.showsNameLabel = showLabels
            // Must set clusteringIdentifier here before returning view, not in init/configure
            // MKMapView makes clustering decisions based on this value at return time
            view.clusteringIdentifier = "contact"
            view.onDetail = { [weak self] in
                self?.onDetailTap?(contactAnnotation.contact)
            }
            view.onMessage = { [weak self] in
                self?.onMessageTap?(contactAnnotation.contact)
            }

            return view
        }

        // Common selection handling extracted for cross-platform use
        private func handleDidSelect(annotation: any MKAnnotation, in mapView: MKMapView) {
            guard !isUpdatingFromSwiftUI else { return }

            if annotation is MKUserLocation { return }

            if let cluster = annotation as? MKClusterAnnotation {
                if let tapTime = lastClusterTapTime, Date().timeIntervalSince(tapTime) < 0.5 {
                    logger.debug("Cluster: didSelect skipped (gesture handled \(Date().timeIntervalSince(tapTime), format: .fixed(precision: 3))s ago)")
                    mapView.deselectAnnotation(cluster, animated: false)
                    return
                }
                logger.debug("Cluster: didSelect calling showAnnotations (fallback path)")
                mapView.deselectAnnotation(cluster, animated: false)
                hasPendingShowAnnotations = true
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                return
            }

            guard let contactAnnotation = annotation as? ContactAnnotation else { return }

            logger.debug("Selection: didSelect for \(contactAnnotation.contact.displayName)")

            if let view = mapView.view(for: annotation) as? ContactPinView {
                view.showsNameLabel = false
            }

            Task { @MainActor in
                logger.debug("Selection: updating selectedContact binding")
                self.setSelectedContact?(contactAnnotation.contact)
            }
        }

        private func handleDidDeselect(annotation: any MKAnnotation, in mapView: MKMapView) {
            guard !isUpdatingFromSwiftUI else { return }

            if let view = mapView.view(for: annotation) as? ContactPinView {
                view.showsNameLabel = showLabels
            }

            Task { @MainActor in
                self.setSelectedContact?(nil)
            }
        }

        #if canImport(UIKit)
        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            handleDidSelect(annotation: annotation, in: mapView)
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: any MKAnnotation) {
            handleDidDeselect(annotation: annotation, in: mapView)
        }
        #else
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            handleDidSelect(annotation: annotation, in: mapView)
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            handleDidDeselect(annotation: annotation, in: mapView)
        }
        #endif

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isUpdatingFromSwiftUI else {
                logger.debug("Region: regionDidChangeAnimated skipped (isUpdatingFromSwiftUI)")
                return
            }

            let newSpan = mapView.region.span.latitudeDelta

            // Handle showAnnotations region changes - must set pendingUserGestureRegion
            // to protect against stale binding values, since the binding wasn't updated
            if hasPendingShowAnnotations {
                logger.debug("Region: regionDidChangeAnimated from showAnnotations (span=\(newSpan, format: .fixed(precision: 4)))")
                hasPendingShowAnnotations = false
                hasPendingProgrammaticRegion = false // Clear if also set
                lastAppliedRegion = mapView.region
                pendingUserGestureRegion = mapView.region
                Task { @MainActor in
                    logger.debug("Region: updating cameraRegion binding (from showAnnotations)")
                    self.setCameraRegion?(mapView.region)
                }
                return
            }

            // Don't overwrite binding during programmatic region changes from setRegion
            if hasPendingProgrammaticRegion {
                logger.debug("Region: regionDidChangeAnimated from programmatic change (span=\(newSpan, format: .fixed(precision: 4)))")
                hasPendingProgrammaticRegion = false
                lastAppliedRegion = mapView.region
                return
            }

            // Don't write back until we've applied at least one programmatic region
            // This prevents the initial default region from overwriting the intended region
            guard hasAppliedInitialRegion else {
                logger.debug("Region: regionDidChangeAnimated before initial region (span=\(newSpan, format: .fixed(precision: 4)))")
                lastAppliedRegion = mapView.region
                return
            }

            // Track user-initiated region changes
            // Mark as pending so stale binding values won't revert this change
            logger.debug("Region: regionDidChangeAnimated setting pendingUserGestureRegion (span=\(newSpan, format: .fixed(precision: 4)))")
            lastAppliedRegion = mapView.region
            pendingUserGestureRegion = mapView.region

            Task { @MainActor in
                logger.debug("Region: updating cameraRegion binding")
                self.setCameraRegion?(mapView.region)
            }
        }
    }
}

// MARK: - Platform Conformance

#if canImport(UIKit)
extension MKMapViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView { _createView(coordinator: context.coordinator) }
    func updateUIView(_ mapView: MKMapView, context: Context) { _updateView(mapView, coordinator: context.coordinator) }
}
#else
extension MKMapViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> MKMapView { _createView(coordinator: context.coordinator) }
    func updateNSView(_ mapView: MKMapView, context: Context) { _updateView(mapView, coordinator: context.coordinator) }
}
#endif

// MARK: - MKCoordinateRegion Comparison

extension MKCoordinateRegion {
    func isApproximatelyEqual(to other: MKCoordinateRegion, tolerance: Double = 0.0001) -> Bool {
        abs(center.latitude - other.center.latitude) < tolerance &&
        abs(center.longitude - other.center.longitude) < tolerance &&
        abs(span.latitudeDelta - other.span.latitudeDelta) < tolerance &&
        abs(span.longitudeDelta - other.span.longitudeDelta) < tolerance
    }
}
