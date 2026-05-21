//
//  FullScreenAlertRouter.swift
//  calkitty
//
//  Created by Jakob Vad Nielsen on 20/05/2026.
//

import SwiftUI

/// Routes a full-screen AlertStyle to the corresponding visual alert view.
/// Used by AlertService to display the correct style in the full-screen panel.
struct FullScreenAlertRouter: View {
    let style: AlertStyle
    let props: FullScreenAlertProps

    var body: some View {
        switch style {
        case .fullScreenGlassmorphic:
            GlassmorphicAlertView(props: props)
        case .fullScreenBoldMinimal:
            BoldMinimalAlertView(props: props)
        case .fullScreenWarmPlayful:
            WarmPlayfulAlertView(props: props)
        case .popupDialog:
            EmptyView()
        }
    }
}
