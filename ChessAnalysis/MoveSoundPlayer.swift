import Foundation
import AVFoundation

enum MoveSoundPlayer {
    private static var players: [String: AVAudioPlayer] = [:]

    static func play(name: String, fileExtension: String) {
        let key = "\(name).\(fileExtension)"
        if let player = players[key] {
            player.currentTime = 0
            player.play()
            return
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[key] = player
            player.play()
        } catch {
            return
        }
    }
}
