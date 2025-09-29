import SwiftUI

/// A view that displays debug messages as an overlay on the camera view
struct DebugOverlayView: View {
    @ObservedObject var model: DebugOverlayModel
    
    // Position of the overlay (default to bottom)
    var position: Position = .bottom
    
    // Overlay position options
    enum Position {
        case top
        case bottom
    }
    
    var body: some View {
        VStack {
            if position == .top {
                messagesList
                Spacer()
            } else {
                Spacer()
                messagesList
            }
        }
        .padding()
    }
    
    private var messagesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(model.messages.reversed(), id: \.id) { message in
                            messageView(for: message)
                    .transition(.opacity.combined(with: .slide))
                    .animation(.easeInOut, value: model.messages)
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 220, alignment: .leading)
    }
    
    private func messageView(for message: DebugOverlayModel.DebugMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(message.type.color)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(message.message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                
                Text(timeString(for: message.timestamp))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
    }
    
    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

//#Preview {
//    ZStack {
//        Color.gray // Simulating camera background
//        
//        DebugOverlayView(model: {
//            let model = DebugOverlayModel()
//            model.addError("Failed to verify license plate")
//            model.addWarning("Low confidence detection (0.67)")
//            model.addInfo("Processing frame #1024")
//            model.addSuccess("Verified: Toyota Camry")
//            return model
//        }())
//    }
//}
