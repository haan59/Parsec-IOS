// import SwiftUI
// import GLKit
//
// struct ParsecGLKViewController: UIViewControllerRepresentable
// {
//	let glkView = GLKView()
//	let glkViewController = GLKViewController()
//	let onBeforeRender:() -> Void
//
//	func makeCoordinator() -> ParsecGLKRenderer
//	{
//		ParsecGLKRenderer(glkView, glkViewController, onBeforeRender)
//	}
//
//	func makeUIViewController(context: UIViewControllerRepresentableContext<ParsecGLKViewController>) -> GLKViewController
//	{
//		glkView.context = EAGLContext(api:.openGLES3)!
//		glkViewController.view = glkView
//		glkViewController.preferredFramesPerSecond = 60
//		return glkViewController
//	}
//
//	func updateUIViewController(_ uiViewController:GLKViewController, context: UIViewControllerRepresentableContext<ParsecGLKViewController>) { }
// }

import UIKit
import GLKit

class ParsecGLKViewController: ParsecPlayground {

	var glkView: GLKView!
	let glkViewController = GLKViewController()
	var glkRenderer: ParsecGLKRenderer!
	let updateImage: () -> Void

	weak var viewController: UIViewController?

	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
		self.viewController = viewController
		self.updateImage = updateImage
	}

	public func viewDidLoad() {
		glkView = GLKView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
		glkRenderer = ParsecGLKRenderer(glkView, glkViewController, updateImage)
		self.viewController?.view.addSubview(glkView)
		setupGLKViewController()
		ParsecBackgroundManager.shared.glkViewController = glkViewController

	}

	private func setupGLKViewController() {
		glkView.context = EAGLContext(api: .openGLES3)!
		glkViewController.view = glkView

		// Use configured FPS or device max (for ProMotion displays)
		glkViewController.preferredFramesPerSecond = SettingsHandler.resolvedFramesPerSecond

		if let parent = viewController {
			parent.addChild(glkViewController)
			parent.view.addSubview(glkViewController.view)
			glkViewController.didMove(toParent: parent)
		}
	}

	var eaglContext: EAGLContext? {
		return glkView?.context
	}

	var renderView: UIView { glkView }

	func cleanUp() {
		guard let context = eaglContext else { return }
		EAGLContext.setCurrent(context)
		CParsec.glDestroy()
	}

	func updateSize(width: CGFloat, height: CGFloat) {
		// bounds + center, not frame: the view may carry a Stretch to Fill transform
		glkView.bounds = CGRect(x: 0, y: 0, width: width, height: height)
		glkView.center = CGPoint(x: width / 2, y: height / 2)
	}

}
