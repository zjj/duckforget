//
//  MyNoteAppWidgetLiveActivity.swift
//  MyNoteAppWidget
//
//  Created by jj.zhong on 19/2/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct MyNoteAppWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct MyNoteAppWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MyNoteAppWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension MyNoteAppWidgetAttributes {
    fileprivate static var preview: MyNoteAppWidgetAttributes {
        MyNoteAppWidgetAttributes(name: "World")
    }
}

extension MyNoteAppWidgetAttributes.ContentState {
    fileprivate static var smiley: MyNoteAppWidgetAttributes.ContentState {
        MyNoteAppWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: MyNoteAppWidgetAttributes.ContentState {
         MyNoteAppWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: MyNoteAppWidgetAttributes.preview) {
   MyNoteAppWidgetLiveActivity()
} contentStates: {
    MyNoteAppWidgetAttributes.ContentState.smiley
    MyNoteAppWidgetAttributes.ContentState.starEyes
}
