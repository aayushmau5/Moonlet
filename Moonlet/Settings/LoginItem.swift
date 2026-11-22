import Foundation
import Observation
import ServiceManagement

@MainActor
protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var statusText = "Off"
    private(set) var errorText: String?
    let developmentWarning: String?

    @ObservationIgnored private let service: LoginItemService

    init(service: LoginItemService = SMAppService.mainApp, bundlePath: String = Bundle.main.bundlePath) {
        self.service = service
        self.developmentWarning = bundlePath.hasPrefix("/Applications/")
            ? nil
            : "This is a development build. Run make install, open /Applications/Moonlet.app, and turn this on there."
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        errorText = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorText = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        switch service.status {
        case .enabled:
            isEnabled = true
            statusText = "Moonlet starts when you log in"
        case .requiresApproval:
            isEnabled = true
            statusText = "Approve Moonlet in System Settings > General > Login Items"
        default:
            isEnabled = false
            statusText = "Off"
        }
    }
}
