//
//  NKViewController.swift
//  NKCamera
//
//  Created by nanoka____ on 2015/07/09.
//  Copyright (c) 2015年 nanoka____. All rights reserved.
//

/*--------------------------------------------------------------------
; import : FrameworkやObjective-cを読み込む場合に使用
---------------------------------------------------------------------*/
import UIKit
import AVFoundation

//フォーカスと露出 https://icons8.com/web-app/7025/inactive-state
//カメラ向き変更 https://icons8.com/web-app/2210/switch-camera
//フラッシュ https://icons8.com/web-app/6704/lightning-bolt
//撮影ボタン https://icons8.com/web-app/2874/integrated-webcam-filled

/*=====================================================================
; NKViewController
======================================================================*/
class NKViewController : UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    enum TapedViewType {
        case Focus
        case Exposure
        case None
    }
    
    var videoInput: AVCaptureDeviceInput?
    var videoDataOutput: AVCaptureVideoDataOutput?
    var session: AVCaptureSession?
    var previewImageView: UIImageView?
    var CAMERA_FRONT: Bool = false
    
    var oNavigationBar: UINavigationBar?
    var oToolbar: UIToolbar?
    
    var viewType: TapedViewType = TapedViewType.None
    var focusView: UIImageView?
    var exposureView: UIImageView?
    
    var adjustingExposure: Bool = false
    
    var takePhotoOverlay: UIImageView?
    
    var flashButton: UIButton?
    var flashQueue: dispatch_queue_t = dispatch_queue_create("com.coma-tech.takingPhotoQueue", DISPATCH_QUEUE_SERIAL)
    var FLASH_MODE: Bool = false
    
    /*--------------------------------------------------------
    ; deinit : 解放
    ;     in :
    ;    out :
    --------------------------------------------------------*/
    deinit {
        AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo).removeObserver(self, forKeyPath: "adjustingExposure")
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    /*-----------------------------------------------------------------
    ; init coder : StoryBoardの利用を禁止するメソッド(必須)
    ;         in : aDecoder(NSCoder)
    ;        out :
    ------------------------------------------------------------------*/
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /*-----------------------------------------------------------------
    ; init : 初期化メソッド(必須)
    ;   in :
    ;  out :
    ------------------------------------------------------------------*/
    init() {
        //インスタンス生成
        super.init(nibName: nil, bundle: nil)
    }
    
    /*-----------------------------------------------------------------
    ; viewDidLoad : 初回Viewの読み込み時に呼び出される
    ;          in :
    ;         out :
    ------------------------------------------------------------------*/
    override func viewDidLoad() {
        //背景を白色にする
        self.view.backgroundColor = UIColor.whiteColor()
        
        //露出のプロパティを監視する
        AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo).addObserver(self, forKeyPath: "adjustingExposure", options: NSKeyValueObservingOptions.New, context: nil)
        
        //マルチタスクから復帰したときに呼ばれる
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationBecomeActive", name: UIApplicationDidBecomeActiveNotification, object: nil)
        
        //マルチタスクから復帰したときに呼ばれる
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "applicationResignActive", name: UIApplicationWillResignActiveNotification, object: nil)
        
        //フラッシュ変更ボタン
        flashButton = UIButton.buttonWithType(UIButtonType.Custom) as? UIButton
        flashButton!.frame = CGRectMake(0, 0, 44, 44);
        flashButton!.setImage(UIImage(named: "flash"), forState: UIControlState.Normal)
        flashButton!.addTarget(self, action: "changeFlashMode:", forControlEvents: UIControlEvents.TouchUpInside)
        let changeFlashButton = UIBarButtonItem(customView: flashButton!)
        
        //カメラ向き変更ボタン
        let changeCameraButton = UIBarButtonItem(image: UIImage(named: "change_camera"), style: UIBarButtonItemStyle.Plain, target: self, action: "changeCamera:")
        
        //ナビゲーションバー
        oNavigationBar = UINavigationBar(frame: CGRectMake(0, 0, self.view.frame.size.width, 44+20))
        self.view.addSubview(oNavigationBar!)
        
        let naviItem:UINavigationItem = UINavigationItem(title: "NKCamera")
        naviItem.leftBarButtonItems = [changeFlashButton]
        naviItem.rightBarButtonItems = [changeCameraButton];
        oNavigationBar!.setItems([naviItem], animated: false)
        
        //スペース
        let spacer = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.FlexibleSpace, target: nil, action: nil)
        
        //撮影ボタン
        let takePhotoButton = UIBarButtonItem(image: UIImage(named: "shutter"), style: UIBarButtonItemStyle.Plain, target: self, action: "takePhoto:")
        
        //ツールバーを生成
        oToolbar = UIToolbar(frame: CGRectMake(0, self.view.frame.size.height-44, self.view.frame.size.width, 44))
        oToolbar!.items = [spacer,takePhotoButton,spacer]
        self.view.addSubview(oToolbar!)
        
        //プレビュー用のビューを生成
        previewImageView = UIImageView(frame: CGRectMake(0, oNavigationBar!.frame.origin.y+oNavigationBar!.frame.size.height, self.view.bounds.size.width, self.view.bounds.size.height - oToolbar!.frame.size.height - (oNavigationBar!.frame.origin.y+oNavigationBar!.frame.size.height)))
        self.view.addSubview(previewImageView!)
        
        //フォーカスビュー
        focusView = UIImageView(frame: CGRectMake(0, 0, 60, 60))
        focusView!.userInteractionEnabled = true;
        focusView!.center = previewImageView!.center;
        focusView!.image = UIImage(named: "focus_circle")
        self.view.addSubview(focusView!)
        
        //露出
        exposureView = UIImageView(frame: focusView!.frame)
        exposureView!.userInteractionEnabled = true;
        exposureView!.image = UIImage(named: "exposure_circle")
        self.view.addSubview(exposureView!)

        //撮影時の黒いオーバーレイ
        takePhotoOverlay = UIImageView(frame: CGRectMake(0, 0, self.view.frame.size.width/2, self.view.frame.size.height/2))
        takePhotoOverlay!.center = self.view.center;
        takePhotoOverlay!.layer.borderWidth = 1.0;
        takePhotoOverlay!.layer.borderColor = UIColor.whiteColor().CGColor
        takePhotoOverlay!.backgroundColor = UIColor.clearColor();
        takePhotoOverlay!.contentMode = UIViewContentMode.ScaleAspectFit;
        takePhotoOverlay!.alpha = 0.0;
        self.view.addSubview(takePhotoOverlay!)

        //撮影準備
        self.setupAVCapture()
    }
    
    /*--------------------------------------------------------
    ; changeFlashMode : フラッシュのモードを変更する
    ;              in : (id)sender
    ;             out :
    --------------------------------------------------------*/
    func changeFlashMode(sender: AnyObject?) {
        FLASH_MODE = !FLASH_MODE;
        if(FLASH_MODE){
            flashButton?.setImage(UIImage(named: "flash_on"), forState: UIControlState.Normal)
        }else{
            flashButton?.setImage(UIImage(named: "flash"), forState: UIControlState.Normal)
        }
    }
    
    /*--------------------------------------------------------
    ; changeCamera : カメラ向き変更ボタン
    ;           in : (id)sender
    ;          out :
    --------------------------------------------------------*/
    func changeCamera(sender : AnyObject) {
        //今と反対の向きを判定
        CAMERA_FRONT = !CAMERA_FRONT;
        var position: AVCaptureDevicePosition! = AVCaptureDevicePosition.Back;
        if(CAMERA_FRONT){
            position = AVCaptureDevicePosition.Front;
        }
        //セッションからvideoInputの取り消し
        session?.removeInput(videoInput);
        let videoDevices = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo);
        var captureDevice: AVCaptureDevice?;
        for device in videoDevices {
            if(device.position == position){
                captureDevice = device as? AVCaptureDevice;
                if(CAMERA_FRONT){
                    //フロントカメラになった
                    if(FLASH_MODE){
                        //フラッシュをOFFにする
                        self.changeFlashMode(nil)
                    }
                    flashButton!.enabled = false;
                }else{
                    flashButton!.enabled = true;
                }
                break;
            }
        }
        
        //  couldn't find one on the front, so just get the default video device.
        if(captureDevice == nil) {
            captureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        }
        videoInput = AVCaptureDeviceInput.deviceInputWithDevice(captureDevice, error: nil) as? AVCaptureDeviceInput
        if(videoInput != nil) {
            session?.addInput(videoInput)
        }
    }
    
    /*--------------------------------------------------------
    ; takePhoto : 撮影ボタン
    ;        in : (id)sender
    ;       out :
    --------------------------------------------------------*/
    func takePhoto(sender: AnyObject) {
        //シャッター音(必要な場合コメント外してください)
//        AudioServicesPlaySystemSound(1108)
        
        if(FLASH_MODE && !CAMERA_FRONT){
            dispatch_sync(flashQueue){
                let camera: AVCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
                if (camera.hasTorch && camera.hasFlash){
                    var error: NSError?
                    if(camera.lockForConfiguration(&error)) {
                        //トーチをONにする
                        camera.torchMode = AVCaptureTorchMode.On
                        //トーチの明るさを調整(0.0〜1.0)
                        camera.setTorchModeOnWithLevel(1.0, error:&error)
                        camera.unlockForConfiguration()
                    }
                }
                sleep(1);
            };
        }
        
        // アルバムに画像を保存
        UIImageWriteToSavedPhotosAlbum(previewImageView?.image, self, "onCompleteCapture:didFinishSavingWithError:contextInfo:", nil);
    }
    
    /*--------------------------------------------------------
    ; onCompleteCapture : 画像保存完了時
    ;                in : (UIImage *)screenImage
    ;                   : (NSError *)error
    ;                   : (void *)contextInfo
    ;               out :
    --------------------------------------------------------*/
    func onCompleteCapture(screenImage:UIImage?, didFinishSavingWithError error:NSError?, contextInfo:AnyObject?) {
        if(error == nil && screenImage != nil){
            //保存成功
            //フラッシュ消灯
            if(FLASH_MODE && !CAMERA_FRONT){
                dispatch_sync(flashQueue) {
                    let captureDeviceClass: AnyClass! = NSClassFromString("AVCaptureDevice");
                    if(captureDeviceClass != nil){
                        let device: AVCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
                        if(device.hasTorch && device.hasFlash){
                            var error: NSError?
                            if(device.lockForConfiguration(&error)) {
                                device.torchMode = AVCaptureTorchMode.Off
                                device.unlockForConfiguration()
                            }
                        }
                    }
                }
            }
            
            //保存画像オーバーレイ
            takePhotoOverlay!.image = screenImage;
            UIView.animateWithDuration(0.2,
                animations:{
                    takePhotoOverlay?.alpha = 1.0
                }, completion:{ finished in
                    //非表示処理
                    UIView.animateWithDuration(0.2,
                        delay: 1.0,
                        options: UIViewAnimationOptions.CurveEaseInOut,
                        animations:{
                            takePhotoOverlay?.alpha = 0.0
                        }, completion:{ finish in
                            takePhotoOverlay?.image = nil
                        }
                    )
                }
            )
        }
    }
    
    /*--------------------------------------------------------
    ; setupAVCapture : カメラキャプチャーの設定
    ;             in :
    ;            out :
    --------------------------------------------------------*/
    func setupAVCapture() {
        var error: NSError?
        
        //入力と出力からキャプチャーセッションを作成
        session = AVCaptureSession()
        
        //画像のサイズ
        session?.sessionPreset = AVCaptureSessionPresetHigh;
        
        //カメラからの入力を作成
        var camera = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        
        //カメラからの入力を作成し、セッションに追加
        videoInput = AVCaptureDeviceInput.deviceInputWithDevice(camera, error:&error) as? AVCaptureDeviceInput
        session?.addInput(videoInput)
        
        //画像への出力を作成し、セッションに追加
        videoDataOutput = AVCaptureVideoDataOutput()
        session?.addOutput(videoDataOutput)
        
        //ビデオ出力のキャプチャの画像情報のキューを設定
        let queue = dispatch_queue_create("myQueue", nil)
        videoDataOutput?.alwaysDiscardsLateVideoFrames = true;
        videoDataOutput?.setSampleBufferDelegate(self, queue: queue)
        
        //ビデオへの出力の画像は、BGRAで出力
        videoDataOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey : NSNumber(integer:kCVPixelFormatType_32BGRA)];
        
        //1秒あたり15回画像をキャプチャ
        if(camera.lockForConfiguration(&error)){
            camera.activeVideoMinFrameDuration = CMTimeMake(1, 15);
            camera.unlockForConfiguration()
        }
    }
    
    /*--------------------------------------------------------
    ; imageFromSampleBuffer : SampleBufferを画像に変換する
    ;                    in : (CMSampleBufferRef)sampleBuffer
    ;                   out : (UIImage *)image
    --------------------------------------------------------*/
    private func imageFromSampleBuffer(sampleBuffer :CMSampleBufferRef) -> UIImage? {
        let imageBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let uint: Int = Int(0)
        
        //ピクセルバッファのベースアドレスをロックする
        CVPixelBufferLockBaseAddress(imageBuffer, 0)
        
        //画像情報の取得
        let baseAddress: UnsafeMutablePointer<Void> = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, uint)
        
        let bytesPerRow: Int = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width: Int = CVPixelBufferGetWidth(imageBuffer)
        let height: Int = CVPixelBufferGetHeight(imageBuffer)
        
        //RGBの色空間
        let colorSpace: CGColorSpaceRef = CGColorSpaceCreateDeviceRGB()
        
        let bitsPerCompornent: Int = 8
        var bitmapInfo = CGBitmapInfo((CGBitmapInfo.ByteOrder32Little.rawValue | CGImageAlphaInfo.PremultipliedFirst.rawValue) as UInt32)
        let newContext: CGContextRef = CGBitmapContextCreate(baseAddress, width, height, bitsPerCompornent, bytesPerRow, colorSpace, bitmapInfo) as CGContextRef
        let imageRef: CGImageRef = CGBitmapContextCreateImage(newContext)
        
        //UIImageに変換
        let resultImage: UIImage? = UIImage(CGImage: imageRef, scale: 1.0, orientation: UIImageOrientation.Right)!
        
        return resultImage
    }
    
    /*========================================================
    ; AVCaptureVideoDataOutputSampleBufferDelegate
    ========================================================*/
    /*--------------------------------------------------------
    ; didOutputSampleBuffer : 新しいキャプチャの情報が追加された時
    ;                    in : (AVCaptureOutput *)captureOutput
    ;                       : (CMSampleBufferRef)sampleBuffer
    ;                       : (AVCaptureConnection *)connection
    ;                   out :
    --------------------------------------------------------*/
    func captureOutput(captureOutput: AVCaptureOutput, didOutputSampleBuffer sampleBuffer: CMSampleBufferRef, fromConnection connection:AVCaptureConnection) {
        //キャプチャしたフレームからCGImageを作成
        var image: UIImage? = self.imageFromSampleBuffer(sampleBuffer)
        
        // 画像を画面に表示
        dispatch_async(dispatch_get_main_queue()) {
            previewImageView?.image = image;
        };
    }
    
    /*========================================================
    ; UIResponder
    ========================================================*/
    /*--------------------------------------------------------
    ; touchesBegan : Viewが触られた時
    ;           in : (NSSet *)touches
    ;              : (UIEvent *)event
    ;          out :
    --------------------------------------------------------*/
    override func touchesBegan(touches: Set<NSObject>, withEvent event: UIEvent) {
        //触られたViewを判定する
        let touch: UITouch = touches.first as! UITouch
        if(touch.view == focusView){
            viewType = TapedViewType.Focus;
        }else if(touch.view == exposureView){
            viewType = TapedViewType.Exposure;
        }else{
            viewType = TapedViewType.None;
        }
    }
    
    /*--------------------------------------------------------
    ; touchesMoved : Viewが触られている時
    ;           in : (NSSet *)touches
    ;              : (UIEvent *)event
    ;          out :
    --------------------------------------------------------*/
    override func touchesMoved(touches: Set<NSObject>, withEvent event: UIEvent) {
        if(viewType != TapedViewType.None){
            let touch: UITouch = touches.first as! UITouch
            let location: CGPoint = touch.locationInView(self.view)
            if(location.x > focusView!.frame.size.width/2){
                if(location.x < self.view.frame.size.width-focusView!.frame.size.width/2){
                    if(location.y > focusView!.frame.size.height/2+oNavigationBar!.frame.origin.y+oNavigationBar!.frame.size.height){
                        if(location.y < self.view.frame.size.height-oToolbar!.frame.size.height-focusView!.frame.size.height/2){
                            //フォーカスか露出をカメラ映像内で移動させる
                            if(viewType == TapedViewType.Focus){
                                focusView?.center = location;
                            }else if(viewType == TapedViewType.Exposure){
                                exposureView?.center = location;
                            }
                        }
                    }
                }
            }
        }
    }
    
    /*--------------------------------------------------------
    ; touchesCancelled : Viewを触るのをキャンセルされた
    ;               in : (NSSet *)touches
    ;                  : (UIEvent *)event
    ;              out :
    --------------------------------------------------------*/
    override func touchesCancelled(touches: Set<NSObject>!, withEvent event: UIEvent!) {
        if(viewType != TapedViewType.None){
            //フォーカスか露出の調整中にキャンセルされた時、正常終了のメソッドも呼ぶ
            self.touchesEnded(touches, withEvent: event)
        }
    }
    
    /*--------------------------------------------------------
    ; touchesEnded : Viewを触り終わった時
    ;           in : (NSSet *)touches
    ;              : (UIEvent *)event
    ;          out :
    --------------------------------------------------------*/
    override func touchesEnded(touches: Set<NSObject>, withEvent event: UIEvent) {
        if(viewType != TapedViewType.None){
            //対象座標を作成
            let touch: UITouch = touches.first as! UITouch
            let location: CGPoint = touch.locationInView(self.view)
            let viewSize: CGSize = self.view.bounds.size;
            let pointOfInterest: CGPoint = CGPointMake(location.y / viewSize.height, 1.0 - location.x / viewSize.width);
            if(viewType == TapedViewType.Focus){
                //フォーカスを合わせる
                var camera: AVCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
                var error: NSError?
                if(camera.isFocusModeSupported(AVCaptureFocusMode.AutoFocus)) {
                    if (camera.lockForConfiguration(&error)) {
                        camera.focusPointOfInterest = pointOfInterest;
                        camera.focusMode = AVCaptureFocusMode.AutoFocus;
                        camera.unlockForConfiguration()
                    }
                }
            }else if(viewType == TapedViewType.Exposure){
                //露出を合わせる
                var camera: AVCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
                var error:NSError?
                if (camera.isExposureModeSupported(AVCaptureExposureMode.ContinuousAutoExposure)){
                    adjustingExposure = true
                    if (camera.lockForConfiguration(&error)) {
                        camera.exposurePointOfInterest = pointOfInterest;
                        camera.exposureMode = AVCaptureExposureMode.ContinuousAutoExposure;
                        camera.unlockForConfiguration()
                    }
                }
            }
            viewType = TapedViewType.None;
        }
    }
    
    /*========================================================
    ; UIApplication
    ========================================================*/
    /*--------------------------------------------------------
    ; applicationBecomeActive : アプリがフォアグラウンドで有効な状態になった時
    ;                      in :
    ;                     out :
    --------------------------------------------------------*/
    func applicationBecomeActive() {
        //カメラの起動
        if(session != nil){
            session!.startRunning()
        }
    }
    
    /*--------------------------------------------------------
    ; applicationResignActive : アプリがバックグラウンドで無効な状態になった時
    ;                      in :
    ;                     out :
    --------------------------------------------------------*/
    func applicationResignActive() {
        //カメラの停止
        if(session != nil){
            session!.stopRunning()
        }
    }
    
    /*========================================================
    ; NSObject(NSKeyValueObserving)
    ========================================================*/
    /*--------------------------------------------------------
    ; observeValueForKeyPath : 露出のプロパティが変更された時
    ;                     in : (NSString *)keyPath
    ;                        : (id)object
    ;                        : (NSDictionary *)change
    ;                        : (void *)context
    ;                    out :
    --------------------------------------------------------*/
    override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject : AnyObject], context: UnsafeMutablePointer<Void>) {
        //露出が調整中じゃない時は処理を返す
        if (!adjustingExposure) {
            return
        }
        
        //露出の情報
        if keyPath == "adjustingExposure" {
            let isNew = change[NSKeyValueChangeNewKey]! as! Bool
            if !isNew {
                //露出が決定した
                self.adjustingExposure = false
                //露出を固定する
                var camera: AVCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
                var error:NSError?
                if (camera.lockForConfiguration(&error)) {
                    camera.exposureMode = AVCaptureExposureMode.Locked
                    camera.unlockForConfiguration()
                }
            }
        }
    }
}