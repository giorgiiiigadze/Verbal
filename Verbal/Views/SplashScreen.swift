//
//  SplashScreen.swift
//  Verbal
//

import SwiftUI

struct SplashScreen: View {
    var body: some View {
        ZStack {
            Color(.royalBlue400)
                .ignoresSafeArea()
            Image(.brandMark)
                .resizable()
                .scaledToFit()
                .frame(width: 96)
                .foregroundStyle(.white)
        }
    }
}
