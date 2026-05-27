import Foundation

enum OverlayCommand: String {
    case showViolation
    case hide
    case exit
}

print("Faraday overlay helper ready")

while let line = readLine() {
    guard let command = OverlayCommand(rawValue: line.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        continue
    }

    switch command {
    case .showViolation:
        print("overlay:showingViolation")
    case .hide:
        print("overlay:hidden")
    case .exit:
        exit(0)
    }
}
