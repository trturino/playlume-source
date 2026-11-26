//
//  ToolbarView.swift
//  Hololink
//
//  Created by Rafael Turino on 3/4/25.
//  Copyright © 2025 Moonlight Game Streaming Project. All rights reserved.
//

import SwiftUI

struct ToolbarView: View {
    @EnvironmentObject private var viewModel: MainViewModel
    var addingHost: Bool
    
    var body: some View {
        Button(action: {
            viewModel.isLoading = true
        }) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
        }
        .buttonBorderShape(.roundedRectangle(radius: 25))
        .frame(width: 44, height: 44)
        Button(action: {
            viewModel.isShowingSettingsPage = true
        }) {
            Image(systemName: "gear")
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
        }
        .buttonBorderShape(.roundedRectangle(radius: 25))
        .frame(width: 44, height: 44)
        Button( action: {
//            addingHost = true
        }) {
            Image(systemName: "plus")
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
//        }.alert(
//            "Enter computer IP or hostname",
//            isPresented: $addingHost
//        ) {
            
            
        }.alert(
            "Unable to add host",
            isPresented: $viewModel.errorAddingHost
        ) {
            Button("Ok", role: .cancel) {
//                isLoading = false
                viewModel.errorAddingHost = true
            }
        } message: {
            Text(viewModel.addHostErrorMessage)
        }

        .buttonBorderShape(.roundedRectangle(radius: 25))
        .frame(width: 44, height: 44)
    }
}
