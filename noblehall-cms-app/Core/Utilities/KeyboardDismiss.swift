import SwiftUI
import UIKit

enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// 點擊輸入框以外區域時收起鍵盤；`cancelsTouchesInView = false` 不影響按鈕與列表點擊。
private struct DismissKeyboardTapInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func dismissKeyboard() {
            Keyboard.dismiss()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension View {
    /// 觸碰輸入框以外區域時收起鍵盤（建議掛在畫面根節點）。
    func dismissKeyboardOnTapOutside() -> some View {
        background(DismissKeyboardTapInstaller())
    }

    /// 捲動時收起鍵盤（List / Form / ScrollView）。
    func dismissKeyboardOnScroll() -> some View {
        scrollDismissesKeyboard(.immediately)
    }

    /// 鍵盤上方「完成」按鈕（多行輸入建議一併使用）。
    func keyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    Keyboard.dismiss()
                }
            }
        }
    }
}
