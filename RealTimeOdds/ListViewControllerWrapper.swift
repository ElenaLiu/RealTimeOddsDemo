import SwiftUI
import UIKit
import RealTimeOddsPackage

struct ListViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ListViewController {
        return ListViewController()
    }

    func updateUIViewController(_ uiViewController: ListViewController, context: Context) {
    }
}
