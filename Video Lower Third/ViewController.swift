//
//  ViewController.swift
//  Video Lower Third
//
//  Created by Christophe Delhaze on 25/11/19.
//  Copyright © 2019 Christophe Delhaze. All rights reserved.
//

import UIKit
import CoreServices
import AVFoundation
import Photos

class ViewController: UIViewController {

    /// To select the source / original video from the camera roll
    private let videoPicker = UIImagePickerController()
    
    /// To resign first responder and dismiss keyboard when the user taps outside of the lower third text field
    private let tapGesture = UITapGestureRecognizer()
    
    /// The url of the source / original video coming from the videoPicker
    private var videoURL: URL?
    
    /// The video asset of the source / original video coming from the videoPicker
    private var videoAsset: PHAsset?
    
    /// The url of the composited video / new video save in a temporary direcrtory
    private var exportedVideoURL: URL?
    
    /// The background task identifier used at the time of export of the new video
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    /// export session used to save the new video. we are using a property of the ViewController to allow the export to be cancelled while the app is in the background the the export takes more than 30 seconds.
    private var assetExportSession: AVAssetExportSession?
    
    /// Observer used to monitor when the video item playback reaches the end.
    private var endTimeObserver: NSObjectProtocol?
    
    /// Player to play the original video
    private lazy var originalVideoPlayer = AVPlayer()
    
    /// Player layer used to display the original video in the originalVideoView
    private lazy var originalPlayerLayer = AVPlayerLayer()
    
    /// Player to preview the new video
    private lazy var previewVideoPlayer = AVPlayer()
    
    /// Player layer used to display the new video in the previewVideoView
    private lazy var previewPlayerLayer = AVPlayerLayer()
    
    
    /// During export, displays the progress of the video export as a blue line on top of the previewVideoView
    @IBOutlet private var exportProgressView: UIProgressView!
    
    /// During export, displays a Compressing Video... text in the previewVideoView
    @IBOutlet private var compressingVideoLabel: UILabel!
    
    /// View used to display the original video
    @IBOutlet private var originalVideoView: UIView!
    
    /// Button used to add the text on top of the video then export the new video to a temporary file and play it in the previewVideoView
    @IBOutlet private var previewVideoButton: UIButton!
    
    /// User text to overlay on top of the original video.
    @IBOutlet private var lowerThirdTextField: UITextField!
    
    /// Used to play the new video
    @IBOutlet private var previewVideoView: UIView!
    
    /// Button to save the new video to the Camera Roll / Photo Library
    @IBOutlet private var saveToPhotoLibraryButton: UIButton!
    
    /// Buttom to open the videoPickerView
    @IBOutlet private var selectVideoButton: UIButton!
    
    /// Button to play / pause the original video once it is loaded
    @IBOutlet private var originalPlayButton: UIButton!
    
    /// Button to play / pause the new video once it is loaded
    @IBOutlet private var previewPlayButton: UIButton!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Initialize the video picker controller.
        initVideoPicker()

        lowerThirdTextField.delegate = self
        
        // Close the keyboard when tapping outside of the lowerThirdTextField
        tapGesture.addTarget(lowerThirdTextField!, action: #selector(self.lowerThirdTextField.resignFirstResponder))
        view.addGestureRecognizer(tapGesture)
        
        // Initialize the 2 video players and related layers.
        initPlayers()
        
        // Keeps the UI appearance in light mode.
        overrideUserInterfaceStyle = .light

    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // size the player layers to the same size as their parent.
        originalPlayerLayer.frame = originalVideoView.bounds
        previewPlayerLayer.frame = previewVideoView.bounds
    }
    
    /**
     With the image background being dark, a light status bar is more readable.
    */
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
    
    /**
     Initialize the video picker and make sure the user grants access to the Photo Library.
    */
    fileprivate func initVideoPicker() {
        // request access to the Photo Library in order to retreive / request the AVAsset from the selected video file and to save the new video to the camera roll.
        // if the status is not .undefined, this function returns immediately otherwise it prompts the user to grant access.
        PHPhotoLibrary.requestAuthorization { [weak self] authorizationStatus in
            switch authorizationStatus {
            case .authorized:
                guard let strongSelf = self else { return }
                
                DispatchQueue.main.async {
                    if UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum) {
                        // Make sure the Camera Roll supports videos
                        guard UIImagePickerController.availableMediaTypes(for: .savedPhotosAlbum)?.contains((kUTTypeMovie as String)) == true else {
                            UIAlertController.showAlert(with: "Error...", message: "Your Camera Roll does not support Videos.", in: strongSelf)
                            strongSelf.selectVideoButton.isEnabled = false
                            
                            return
                        }
                        strongSelf.videoPicker.sourceType = .savedPhotosAlbum
                        strongSelf.videoPicker.mediaTypes = [(kUTTypeMovie as String)]
                        strongSelf.videoPicker.delegate = strongSelf
                    } else {
                        UIAlertController.showAlert(with: "Error...", message: "To be able to use this app, you need a device with a Camera Roll.", in: strongSelf)
                        strongSelf.selectVideoButton.isEnabled = false
                    }
                }
            default:
                guard let strongSelf = self else { return }
                
                UIAlertController.showAlert(with: "Error...", message: "To use this app, you need to allow access to your Photo Library. Please go to the Settings App -> Privacy -> Photos -> Video Lower Third and select Read and Write access.", in: strongSelf)
                // if we don't have access to the PhotoLibrary, we disable the select video buttom, this way the app cannot be used.
                strongSelf.selectVideoButton.isEnabled = false
            }
        }
    }

    /**
     Initialize the original and preview video players, player layers and play buttons.
     */
    fileprivate func initPlayers() {
        //Init the playerlayers
        originalPlayerLayer.player = originalVideoPlayer
        previewPlayerLayer.player = previewVideoPlayer
        originalVideoView.layer.addSublayer(originalPlayerLayer)
        previewVideoView.layer.addSublayer(previewPlayerLayer)
        
        // Add observer to reset the videos once they have played to the end.
        endTimeObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil, queue: nil) { [weak self] notification in
            if let playerItem = notification.object as? AVPlayerItem {
                if self?.originalVideoPlayer.currentItem == playerItem {
                    self?.originalVideoPlayer.seek(to: CMTime.zero)
                    self?.originalPlayButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
                } else {
                    self?.previewVideoPlayer.seek(to: CMTime.zero)
                    self?.previewPlayButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
                }
            }
        }
    }
    
    deinit {
        if let endTimeObserver = endTimeObserver {
            NotificationCenter.default.removeObserver(endTimeObserver)
        }
    }
    
    /**
     display the videoPicker when the user taps on the selectVideoButton
     */
    @IBAction func selectVideoButtonTapped(_ sender: UIButton) {
        present(videoPicker, animated: true)
    }
    
    /**
     Load the original or new video in their respective players
        - Parameters:
            - url: The url of the video to load
            - player: The player to use to play the video
            - playButton: The play / pause button linked to that player
     */
    private func loadVideo(from url: URL, in player: AVPlayer, playButton: UIButton) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        togglePlayback(for: player, playButton: playButton)
        playButton.isHidden = false
    }
    
    /**
     Enables and disables the preview video based on the content of lowerThirdTextField
     */
    fileprivate func setPreviewVideoButtonState() {
        previewVideoButton.isEnabled = !(lowerThirdTextField.text?.trimmingCharacters(in: CharacterSet(charactersIn: " ")).isEmpty ?? true)
    }
    
    /**
     When the text in lowerThirdTextField change, we call the setPreviewVideoButtonState
     */
    @IBAction func lowerThirdTextChanged(_ sender: UITextField) {
        setPreviewVideoButtonState()
    }
    
    /**
     The user tapped the previewVideoButton. We start compositing the text on top of the original video then export it and preview it.
     */
    @IBAction func previewVideoButtonTapped(_ sender: UIButton) {

        // If we don't have a videoAsset, we cannot process.
        guard let videoAsset = videoAsset else {
            UIAlertController.showAlert(with: "Error...", message: "Invalid Source Video. Please select another video and try again.", in: self)
            return
        }
        
        // To prevent user from trying to preview several times.
        previewVideoButton.isEnabled = false
        
        // Close the keyboard in case the user tapped on the Preview Video button while it was still visible.
        if lowerThirdTextField.isFirstResponder {
            lowerThirdTextField.resignFirstResponder()
        }
        
        // Get the lowere third text while on the main thread
        let lowerThirdText = lowerThirdTextField.text
        
        // Empty the previewVideoView / previewVideoPlayer before exporting
        previewVideoPlayer.replaceCurrentItem(with: nil)
        previewPlayButton.isHidden = true
        
        // Get all the tracks from the original video as well as other information about the original video.
        PHImageManager.default().requestAVAsset(forVideo: videoAsset, options: nil) { [weak self] avAsset, _, _ in
            
            // We cannot proceed without the AVAsset.
            guard let avAsset = avAsset else {
                guard let strongSelf = self else { return }
                
                UIAlertController.showAlert(with: "Error...", message: "Invalid Source Video. Please select another video and try again.", in: strongSelf)
                return
            }
            
            // We add the text on top of the original video then export it.
            self?.addOverlayText(lowerThirdText, to: avAsset ) { url, error in
                guard let url = url else {
                    guard let strongSelf = self else { return }
                    
                    if let error = error {
                        UIAlertController.showAlert(with: "Error...", message: "Failed to render the new video with error: \(error.localizedDescription). Please try again.", in: strongSelf)
                        strongSelf.previewVideoButton.isEnabled = true
                    } else {
                        UIAlertController.showAlert(with: "Error...", message: "Failed to render the new video. Please try again.", in: strongSelf)
                        strongSelf.previewVideoButton.isEnabled = true
                    }
                    return
                }
                
                guard let strongSelf = self else { return }
                
                // save the url of the successfully export new video
                strongSelf.exportedVideoURL = url
                
                // Load the new video in the previewPlayer and enable the button to save the new video  to the photo library.
                DispatchQueue.main.async {
                    strongSelf.loadVideo(from: url, in: strongSelf.previewVideoPlayer, playButton: strongSelf.previewPlayButton)
                    strongSelf.saveToPhotoLibraryButton.isEnabled = true
                }
            }
        }
    }
    
    /**
     The user tapped to save the video to the Photo Library.
     */
    @IBAction func saveToPhotoLibraryButtonTapped(_ sender: UIButton) {
        
        // Original code to save to the Photo Library was added to a closure to demonstrate the use of a UIAlertController to prompt text from the user.
        // In a commercial version the code in saveToPhotoLibrary would be used directly.
        let saveToPhotoLibrary: () -> Void = { [weak self] in
            if let url = self?.exportedVideoURL {
                // Create a new asset in the Photo Library using the new video url we just created.
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { saved, error in
                    guard let strongSelf = self else { return }
                    
                    // Inform the user of the result of the process
                    DispatchQueue.main.async {
                        if saved {
                            UIAlertController.showAlert(with: "Success...", message: "Video successfully saved to your Photo Library.", in: strongSelf)
                            strongSelf.resetApp()
                        } else if let error = error {
                            UIAlertController.showAlert(with: "Error...", message: "Video failed to save to your Photo Library with error: \(error.localizedDescription).", in: strongSelf)
                        } else {
                            UIAlertController.showAlert(with: "Error...", message: "Video failed to save to your Photo Library.", in: strongSelf)
                        }
                    }
                }
            }
        }
        
         saveToPhotoLibrary()
        
//        // Create the alert to prompt the user for a written confirmation.
//        let alert = UIAlertController(title: "Confirmation...", message: "Are you sure you want to save the video to your Camera Roll?\n\n Please type YES and click OK to confirm", preferredStyle: .alert)
//
//        // Add the text field where the user will have to enter YES.
//        alert.addTextField { (textField) in
//            textField.placeholder = "Please type YES here."
//        }
//
//        // Add the OK button and validate the user input.
//        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
//            if let textField = alert.textFields?.first, textField.text == "YES" {
//                saveToPhotoLibrary()
//            } else {
//                // Text was incorrect, we ask again
//                self?.present(alert, animated: true)
//            }
//        }))
//
//        // Add the cancel button.
//        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
//
//        // Display the alert.
//        present(alert, animated: true)
        
    }
    
    /**
     Play or pause the video based on the current status and change the button image accordingly
        - Parameters:
            - player: The player to toggle
            - playButton: The play button to toggle
     */
    fileprivate func togglePlayback(for player: AVPlayer, playButton: UIButton) {
        if player.timeControlStatus == .playing {
            player.pause()
            playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        } else {
            player.play()
            playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
    }
    
    /**
     The user wants to play / pause the original video
     */
    @IBAction func originalPlayButtonTapped(_ sender: UIButton) {
        togglePlayback(for: originalVideoPlayer, playButton: originalPlayButton)
    }
    
    /**
     The user wants to play / pause the preview video
     */
    @IBAction func previewPlayButtonTapped(_ sender: UIButton) {
        togglePlayback(for: previewVideoPlayer, playButton: previewPlayButton)
    }
    
    /**
     Reset the app to it's original state. We do that once the new video has been saved to the Photo Library to preparethe app for a new original video.
    */
    private func resetApp() {
        originalVideoPlayer.replaceCurrentItem(with: nil)
        previewVideoPlayer.replaceCurrentItem(with: nil)
        lowerThirdTextField.text = nil
        videoURL = nil
        videoAsset = nil
        previewVideoButton.isEnabled = false
        saveToPhotoLibraryButton.isEnabled = false
        lowerThirdTextField.isEnabled = false
        originalPlayButton.isHidden = true
        previewPlayButton.isHidden = true

        if let url = exportedVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportedVideoURL = nil
    }
    
    /**
     Add all the tracks that were in the original video asset and were not video tracks
     - Parameters:
        - composition: Final composition used to mix all the tracks together
        - videoAsset: The original asset coming from the Photo Library and containing a list of all the tracks
    */
    private func addRemainingTracks(from videoAsset: AVAsset, to composition: AVMutableComposition) {
        // loop on all the tracks
        for track in videoAsset.tracks {
            // exclude video tracks
            if track.mediaType != .video {
                // if the track timerange is valid, we add it to the composition
                if track.timeRange.isValid {
                    if let compositionTrack = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: track.trackID) {
                        if (try? compositionTrack.insertTimeRange(track.timeRange, of: track, at: track.timeRange.start)) == nil {
                            UIAlertController.showAlert(with: "Error...", message: "Could not add all original tracks to the new video.", in: self)
                            return
                        }
                    }
                }
            }
        }
    }
    
    /**
     This fuction adds the user text on the lower third area of the original video and exports a new video to a temporary file.
        - Parameters:
            - lowerThirdText: The text to overlay on the lower third part of the original video.
            - avAsset: The AVAsset of the original video. Used to get the original tracks and information about the video
            - A completion handler called when the function return.
            - Parameters:
             - url: The url of the new video file. Returns nil if the process failed.
             - error: An error describing why the process failed if it did. Returns nil if the process failed or if we don't have an error object.
    */
    private func addOverlayText(_ lowerThirdText: String?, to avAsset: AVAsset, completionHandler: @escaping(_ url: URL?, _ error: Error?)->()) {
        do {
            // Create the composition for the new video.
            let composition = AVMutableComposition()
            
            // Get the first video track.
            guard let videoTrack = avAsset.tracks(withMediaType: .video).first else {
                UIAlertController.showAlert(with: "Error...", message: "The selected video file doesn't seem to have a video track. Please select another one", in: self)
                completionHandler(nil, nil)
                
                return
            }
            
            // Fix the video track orientation.
            var isVideoInPortraitMode = false
            let videoTrackTransform = videoTrack.preferredTransform;
            if (videoTrackTransform.a == 0 && videoTrackTransform.b == 1.0 && videoTrackTransform.c == -1.0 && videoTrackTransform.d == 0) ||
               (videoTrackTransform.a == 0 && videoTrackTransform.b == -1.0 && videoTrackTransform.c == 1.0 && videoTrackTransform.d == 0) {
                isVideoInPortraitMode = true
            }
            let naturalSize = (isVideoInPortraitMode) ? CGSize(width: videoTrack.naturalSize.height, height: videoTrack.naturalSize.width) : videoTrack.naturalSize
            let width = naturalSize.width
            let height = naturalSize.height

            // Set the time range of the new video equals to the duration of the original video.
            let duration = avAsset.duration
            let videoTimeRange = CMTimeRangeMake(start: CMTime.zero, duration: duration)
            
            // Add original video track
            let compositionVideoTrack: AVMutableCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: videoTrack.trackID)!
            try compositionVideoTrack.insertTimeRange(videoTimeRange, of: videoTrack, at: CMTime.zero)
            compositionVideoTrack.preferredTransform = videoTrack.preferredTransform
            
            // Add Lower Third Text
            // Set up layers
            
            // Original video layer
            let videolayer = CALayer()
            videolayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            videolayer.opacity = 1.0
            
            // Text layer
            let textLayer = CATextLayer()
            textLayer.font = "Courier-BoldOblique" as CFString
            // Actual space available (lower third)
            var lowerThirdHeight = height / 3
            // Good font for space available
            var fontSize: CGFloat = lowerThirdHeight / 1.5
            
            // Make sure that the text width fits in the video
            let font = UIFont(name: "Courier-BoldOblique", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
            let textWidth = lowerThirdText?.width(usingFont: font) ?? (font.lineHeight + fontSize / 10)
            
            // if the text is too wide, we reduce the font size.
            if textWidth > width {
                let ratio = width/textWidth * 0.9 // 0.9 to give some padding to the text.
                lowerThirdHeight *= ratio
                fontSize *= ratio
            }
            
            textLayer.fontSize = fontSize
            textLayer.frame = CGRect(x: 0, y: 0, width: width, height: lowerThirdHeight)
            textLayer.string = lowerThirdText
            textLayer.alignmentMode = CATextLayerAlignmentMode.center
            textLayer.foregroundColor = UIColor.white.cgColor

//            let image = UIImage(named: "Lo3RD-bg")?.cgImage
//            let imageLayer = CALayer()
//            imageLayer.contents = image
//            imageLayer.opacity = 0.5
//            imageLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            
            // Overlay layer
            let overlayLayer = CALayer()
//            overlayLayer.addSublayer(imageLayer)
            overlayLayer.addSublayer(textLayer)
            overlayLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            overlayLayer.masksToBounds = true
            
            // Combine layers
            let parentlayer = CALayer()
            parentlayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
            parentlayer.addSublayer(videolayer)
            parentlayer.addSublayer(overlayLayer)
            
            // Create the video composition
            let videoComposition = AVMutableVideoComposition()
            videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
            videoComposition.renderScale = 1.0
            videoComposition.renderSize = naturalSize
            
            // Enable animation for video layers
            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayers: [videolayer], in: parentlayer)

            // Instruction for the composition
            let compositionInstruction = AVMutableVideoCompositionInstruction()
            compositionInstruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: composition.duration)
    
            // Instruction for the videoTrack
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            layerInstruction.setTransform(videoTrack.preferredTransform, at: CMTime.zero)
            
            // Add layer instructions to the composition instructions
            compositionInstruction.layerInstructions = [layerInstruction] as [AVVideoCompositionLayerInstruction]
            
            // Add the composition Instructions to the video composition
            videoComposition.instructions = [compositionInstruction] as [AVVideoCompositionInstructionProtocol]

            // Add remaining tracks.
            addRemainingTracks(from: avAsset, to: composition)
            
            // URL where the new video will be saved.
            let exportURL = URL(fileURLWithPath: NSTemporaryDirectory() + "/previewVideo.mov")
            
            // Delete destination URL if it exists.
            if FileManager.default.fileExists(atPath: exportURL.path) {
                guard let _ = try? FileManager.default.removeItem(at: exportURL) else {
                    UIAlertController.showAlert(with: "Error...", message: "Unable to delete the temporary video file. Please close the app and try again", in: self)

                    completionHandler(nil, nil)
                    return
                }
            }

            // Export the new video composition
            assetExportSession = AVAssetExportSession(asset: composition, presetName:AVAssetExportPresetHighestQuality)
            if let assetExportSession = assetExportSession {
                
                // Make sure that the device doesn't got to sleep during the export process.
                DispatchQueue.main.async {
                    UIApplication.shared.isIdleTimerDisabled = true
                }

                // Create a dispatch group that is active during the export process and enter it. This is to allow us to disolay a progress bar of the process.
                let exportDispatchGroup = DispatchGroup()
                exportDispatchGroup.enter()

                assetExportSession.outputFileType = AVFileType.mov
                assetExportSession.outputURL = exportURL
                assetExportSession.videoComposition = videoComposition

                UIAlertController.showAlert(with: "Warning...", message: "Please do not leave the app or lock your device while the new video is being exported. If you do so, the process will fail within 30 seconds.", in: self)
                
                // Tell iOS that we need the app to stay alive temporarily while in the background.
                registerBackgroundTask()
                
                // Export the new video asynchronously.
                assetExportSession.exportAsynchronously(completionHandler: { [weak self] in
                    
                    // Once the export is finished, we can leave the group.
                    exportDispatchGroup.leave()

                    // We reactivate the idle timer to allow the device to go to sleep again.
                    DispatchQueue.main.async {
                        UIApplication.shared.isIdleTimerDisabled = false
                    }

                    // Call the completionHandler with the right parameters depending on the export status.
                    switch assetExportSession.status {
                    case AVAssetExportSessionStatus.failed:
                        completionHandler(nil, assetExportSession.error)
                    case AVAssetExportSessionStatus.cancelled:
                        completionHandler(nil, assetExportSession.error)
                    default:
                        completionHandler(exportURL, nil)
                    }
                    
                    // Inform iOS that we are done with our task that was requiring background time.
                    self?.endBackgroundTask()
                })
                
                // This function will monitor the export dispatch group and display the progress in a progressView at the top of the previewVideoView
                displayExportStatus(for: assetExportSession, exportDispatchGroup: exportDispatchGroup)
                
            } else {
                UIAlertController.showAlert(with: "Error...", message: "Failed to export the new video with error: Failed to create export session. Please try again.", in: self)
                
                // Reactivate the preview video button to let the user try again.
                previewVideoButton.isEnabled = true
            }
        } catch {
            UIAlertController.showAlert(with: "Error...", message: "Failed to render the new video with error: \(error.localizedDescription). Please try again.", in: self)
            
            // Reactivate the preview video button to let the user try again.
            previewVideoButton.isEnabled = true
        }
    }
    
    
    // MARK: - Background task management

    /**
      Register a background task right before exporting the new video. This allows for small videos to export in the background (export time < 30 second). If the export time is more than 30 seconds, we cancel the export.
     */
    func registerBackgroundTask() {
        
        // Begin the background task
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            
            // The time alloted to run in the background is about to run out. If the export is still ongoing, we cancel it.
            if self?.assetExportSession?.status == .exporting {
                self?.assetExportSession?.cancelExport()
            }
            
            // Let iOS know we finished our background task
            self?.endBackgroundTask()
        }

        // For testing purpose, make sure the background task is valid.
        assert(backgroundTask != .invalid)
    }
      
    /**
     Once the export is finished, we end the background task to avoid iOS to kill the app.
     */
    func endBackgroundTask() {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
    
    // MARK: - Display Export Progress
    
    /**
      Check export session status and display progress while exporting.
        - Parameters:
            - exportSession: Session currently exporting the new video
            - group: The dispatch group wrapping the export session
    */
    private func displayExportStatus(for exportSession: AVAssetExportSession, exportDispatchGroup: DispatchGroup) {
        
        // Display the progressView and the Compressing Video... Label.
        DispatchQueue.main.async {
            self.exportProgressView.isHidden = false
            self.compressingVideoLabel.isHidden = false
        }

        // we only need to display the progress if the export session is waiting to export or exporting.
        while exportSession.status == .waiting || exportSession.status == .exporting {
            // Update the progressView with the current exportSession progress value.
            DispatchQueue.main.async {
                self.exportProgressView.progress = exportSession.progress
            }
            
            // Wait for the export dispatch group to be over (exportDispatchGroup.leave())
            // _ = we disregard the return of the function as we do not need to know if it timed out or if the exportDispatchGroup.leave() was called
            _ = exportDispatchGroup.wait(timeout: .now() + 0.1)
        }

        // Hide the progressView and Compressing Video... label and reset the progressView to 0.
        DispatchQueue.main.async {
            self.exportProgressView.isHidden = true
            self.compressingVideoLabel.isHidden = true
            self.exportProgressView.progress = 0
        }
    }
    
}

// MARK: - Image Picker Delegate

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    /**
     Picker was cancelled, we close it.
     */
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        videoPicker.dismiss(animated: true)
    }
    
    /**
     The user selected a video.
     */
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        // Make sure we have a valid URL and a valid video asset
        guard let url = info[.mediaURL] as? URL, let asset = info[.phAsset] as? PHAsset else {
            UIAlertController.showAlert(with: "Error...", message: "The movie you selected is invalid. Please select another one and try again.", in: self)
            videoPicker.dismiss(animated: true)
            return
        }
        
        // Store the videoAsset and VideoURL from the selected video
        videoAsset = asset
        videoURL = url
        
        // Load and play the selected video.
        loadVideo(from: url, in: originalVideoPlayer, playButton: originalPlayButton)
        
        // Clear the preview player in case it had a video loaded and hide the previewPlayButton.
        previewVideoPlayer.replaceCurrentItem(with: nil)
        previewPlayButton.isHidden = true
        
        // Allow the user to enter the text to overlay
        lowerThirdTextField.isEnabled = true

        // Nothing to save just yet, we can disable this.
        saveToPhotoLibraryButton.isEnabled = false

        // Adjust the previewVideoButton stsate base on the lowerThirdTextField content.
        setPreviewVideoButtonState()
            
        // We are done, we can close the videoPicker.
        videoPicker.dismiss(animated: true)
    }
    
}

// MARK: - Text Field Delegate

extension ViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Hide the keyboard when the return key is tapped.
        textField.resignFirstResponder()
        
        return false
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Enable the tapGesture since the lowerThirdTextField is now the first responder.
        tapGesture.isEnabled = true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
        // The lowerThirdTextField is not longer first responder. We don't need the tapGesture for now.
        tapGesture.isEnabled = false
    }
    
}

