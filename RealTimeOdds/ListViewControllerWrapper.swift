//
//  Untitled.swift
//  RealTimeOddsPackage
//
//  Created by Elena on 2025/9/24.
//

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
