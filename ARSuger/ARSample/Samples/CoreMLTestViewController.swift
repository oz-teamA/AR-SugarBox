//
//  CoreMLTestViewController.swift
//  ARSample
//
//  Created by yasue kouki on 2021/04/29.
//

import UIKit
import SceneKit
import ARKit
import Vision

class CoreMLTestViewController: UIViewController, ARSCNViewDelegate {
    
    @IBOutlet weak var sceneView: ARSCNView!
    let scene = SCNScene()
    
    var select_object: String = "suger_box6"
    
    var requests = [VNRequest]()
    
    var bufferSize: CGSize = .zero
    var rootLayer: CALayer! = nil
    var detectionOverlay: CALayer! = nil
    var previewLayer: AVCaptureVideoPreviewLayer! = nil
    let session = AVCaptureSession()
    
    @IBOutlet weak var identifyLabel: UILabel!
    @IBOutlet weak var confidenceLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.showsStatistics = true
        sceneView.scene = scene
        sceneView.debugOptions = [.showWorldOrigin, .showFeaturePoints]
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = false
        
        guard let model = try? VNCoreMLModel(for: KakuAug().model) else {
            fatalError()
        }
        let request = VNCoreMLRequest(model: model, completionHandler: { (request, error) in
            //帰ってきた結果がrequest.resultsに格納されている
           DispatchQueue.main.async(execute: {
               if let results = request.results {
                    self.RequestResults(results)
               }
           })
       })
        request.imageCropAndScaleOption = .scaleFit
        requests = [request]
        
        //オブジェクト検出時のboundingBox表示用
        setupLayers()
        
        loopCoreMLUpdate()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    //MRAK: - TAPしてからオブジェクト表示の部分
    @IBAction func tapped(_ sender: UITapGestureRecognizer) {
        if let node = sceneView.scene.rootNode.childNode(withName: "all", recursively: false) {
            node.removeFromParentNode()
        }
        
        // タップされた位置を取得する
        let sceneView = sender.view as! ARSCNView
        let tapLocation = sender.location(in: sceneView)
        
        // ここで角砂糖の個数を求める関数を呼ぶ
        let sugerBox = self.getSugerBox()
        
        // タップされた位置のARアンカーを探す
        let hitTest = sceneView.hitTest(tapLocation, types: .existingPlaneUsingExtent)
        if !hitTest.isEmpty {
            let all = SCNNode()
            all.name = "all"
            // タップした箇所が取得できていればitemを追加
            for i in 0 ..< sugerBox {
                let node = self.addObject(hitTestResult: hitTest.first!, num: i)
                all.addChildNode(node)
            }
            sceneView.scene.rootNode.addChildNode(all)
        }
    }

    //配置メソッド
    func addObject(hitTestResult: ARHitTestResult, num: Int) -> SCNNode {
        let object_name = select_object
        // アセットより、シーンを作成
        let url = Bundle.main.url(forResource: "art.scnassets/\(object_name)", withExtension: "usdz")!
        let scene = try! SCNScene(url: url, options: [.checkConsistency: true])
        
        // ノード作成
        let node = scene.rootNode.childNode(withName: object_name, recursively: false)!

        // 現実世界の座標を取得
        let transform = hitTestResult.worldTransform
        let thirdColumn = transform.columns.3

        // アイテムの配置
        node.position = SCNVector3(thirdColumn.x, thirdColumn.y + 0.05 * Float(num), thirdColumn.z) // 縦に積む
        node.scale = SCNVector3(0.02, 0.02, 0.02)
        // sceneView.scene.rootNode.addChildNode(node)
        return node
    }

    
    //MARK: - CoreML関連の設定部分
    
    func RequestResults(_ results: [Any]) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        detectionOverlay.sublayers = nil
        
        var topValue:Float = Float(-100);
        
        for observation in results where observation is VNClassificationObservation {
            guard let objectObservation = observation as? VNClassificationObservation else {
                continue
            }
            
//            print(objectObservation.identifier)
//            print(objectObservation.confidence)
            
            if(topValue < objectObservation.confidence){
                topValue = objectObservation.confidence
                identifyLabel.text = String(objectObservation.identifier)
                confidenceLabel.text = String(objectObservation.confidence)
            }
            
        }
        
        
        // Recognizedは使用していない
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            //信頼度が一番高いオブジェクト
            let topLabelObservation = objectObservation.labels[0]
            print(topLabelObservation.identifier) //オブジェクト名
            print(topLabelObservation.confidence) //信頼度
            identifyLabel.text = String(topLabelObservation.identifier)
            confidenceLabel.text = String(topLabelObservation.confidence)
            
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
            
            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)
            let textLayer = self.createTextSubLayerInBounds(objectBounds,
                                                            identifier: topLabelObservation.identifier,
                                                            confidence: topLabelObservation.confidence)
            
            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)
        }
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    
    func getSugerBox()->Int{
        if (identifyLabel.text=="orange"){
            return 5;
        }
        else if(identifyLabel.text=="cola"){
            return 10;
        }
        return 1;
    }
    
    func loopCoreMLUpdate() {
        DispatchQueue.main.async {
            self.updateCoreML()
            self.loopCoreMLUpdate()
        }
        
    }

    func updateCoreML() {
        let pixbuff : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        if pixbuff == nil { return }
        let ciImage = CIImage(cvPixelBuffer: pixbuff!)
        let RequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try RequestHandler.perform(requests)
        } catch {
            print(error)
        }
    }
    
    //MARK: - オブジェクト検出時のBoundingBox用の設定部分
    
    func setupLayers() {
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
        do {
            try  videoDevice!.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice?.activeFormat.formatDescription)!)
            bufferSize.width = CGFloat(dimensions.width)
            bufferSize.height = CGFloat(dimensions.height)
            videoDevice!.unlockForConfiguration()
        } catch {
            print(error)
        }
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        rootLayer = sceneView.layer
        previewLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(previewLayer)
        
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        //detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
    }
    
    func updateLayerGeometry() {
        let bounds = rootLayer.bounds
        var scale: CGFloat
        
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1.0
        }
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
        
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.2, 1.0, 1.0, 0.2])
        shapeLayer.cornerRadius = 7
        return shapeLayer
    }
    
}
