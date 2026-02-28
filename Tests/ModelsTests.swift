import Foundation

enum ModelsTests {
    static func runAll() {
        testPartnerLoginDecode()
        testUserLoginDecode()
        testStationListDecode()
        testPlaylistItemDecode()
        testPlaylistItemBestUrl()
        testPandoraResponseError()
        testPlaylistItemAdDetection()
        testLastStationSelection()
    }

    static func testPartnerLoginDecode() {
        let json = """
        {
            "stat": "ok",
            "result": {
                "partnerId": "42",
                "partnerAuthToken": "tok123",
                "syncTime": "abcdef1234567890",
                "stationCreationAdUrl": null
            }
        }
        """.data(using: .utf8)!

        do {
            let resp = try JSONDecoder().decode(PandoraResponse<PartnerLoginResult>.self, from: json)
            TestRunner.assert(resp.isOk, "partner login stat ok")
            TestRunner.assertEqual(resp.result?.partnerId ?? "", "42", "partner login partnerId")
            TestRunner.assertEqual(resp.result?.partnerAuthToken ?? "", "tok123", "partner login token")
        } catch {
            TestRunner.assert(false, "partner login decode: \(error)")
        }
    }

    static func testUserLoginDecode() {
        let json = """
        {
            "stat": "ok",
            "result": {
                "userId": "12345",
                "userAuthToken": "userTok456",
                "canListen": true,
                "hasAudioAds": false
            }
        }
        """.data(using: .utf8)!

        do {
            let resp = try JSONDecoder().decode(PandoraResponse<UserLoginResult>.self, from: json)
            TestRunner.assert(resp.isOk, "user login stat ok")
            TestRunner.assertEqual(resp.result?.userId ?? "", "12345", "user login userId")
            TestRunner.assertEqual(resp.result?.canListen ?? false, true, "user login canListen")
        } catch {
            TestRunner.assert(false, "user login decode: \(error)")
        }
    }

    static func testStationListDecode() {
        let json = """
        {
            "stat": "ok",
            "result": {
                "stations": [
                    {
                        "stationId": "s1",
                        "stationName": "My Station",
                        "stationToken": "st1",
                        "isQuickMix": false
                    },
                    {
                        "stationId": "s2",
                        "stationName": "Quick Mix",
                        "stationToken": "st2",
                        "isQuickMix": true
                    }
                ],
                "checksum": "abc123"
            }
        }
        """.data(using: .utf8)!

        do {
            let resp = try JSONDecoder().decode(PandoraResponse<StationListResult>.self, from: json)
            TestRunner.assert(resp.isOk, "station list stat ok")
            TestRunner.assertEqual(resp.result?.stations.count ?? 0, 2, "station list count")
            TestRunner.assertEqual(resp.result?.stations[0].stationName ?? "", "My Station", "station name")
            TestRunner.assertEqual(resp.result?.stations[1].isQuickMix ?? false, true, "quick mix flag")
        } catch {
            TestRunner.assert(false, "station list decode: \(error)")
        }
    }

    static func testPlaylistItemDecode() {
        let json = """
        {
            "stat": "ok",
            "result": {
                "items": [
                    {
                        "trackToken": "track1",
                        "artistName": "Artist",
                        "albumName": "Album",
                        "songName": "Song Title",
                        "songRating": 0,
                        "albumArtUrl": "https://example.com/art.jpg",
                        "audioUrlMap": {
                            "highQuality": {
                                "bitrate": "192",
                                "encoding": "aacplus",
                                "audioUrl": "https://example.com/high.m4a",
                                "protocol": "http"
                            },
                            "mediumQuality": {
                                "bitrate": "128",
                                "encoding": "aacplus",
                                "audioUrl": "https://example.com/med.m4a",
                                "protocol": "http"
                            },
                            "lowQuality": {
                                "bitrate": "64",
                                "encoding": "aacplus",
                                "audioUrl": "https://example.com/low.m4a",
                                "protocol": "http"
                            }
                        }
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        do {
            let resp = try JSONDecoder().decode(PandoraResponse<PlaylistResult>.self, from: json)
            TestRunner.assert(resp.isOk, "playlist stat ok")
            let item = resp.result!.items[0]
            TestRunner.assertEqual(item.songName ?? "", "Song Title", "playlist song name")
            TestRunner.assertEqual(item.artistName ?? "", "Artist", "playlist artist")
            TestRunner.assert(!item.isAd, "playlist item not ad")
        } catch {
            TestRunner.assert(false, "playlist decode: \(error)")
        }
    }

    static func testPlaylistItemBestUrl() {
        // Test URL priority: high > medium > low
        let item = PlaylistItem(
            trackToken: "t1", artistName: "A", albumName: "B", songName: "C",
            songRating: 0, albumArtUrl: nil, additionalAudioUrl: ["https://fallback.m4a"],
            audioUrlMap: AudioUrlMap(
                highQuality: AudioUrl(bitrate: "192", encoding: "aac", audioUrl: "https://high.m4a", protocol_: "http"),
                mediumQuality: AudioUrl(bitrate: "128", encoding: "aac", audioUrl: "https://med.m4a", protocol_: "http"),
                lowQuality: nil
            ),
            songDetailUrl: nil, stationId: nil, songIdentity: nil, adToken: nil
        )
        TestRunner.assertEqual(item.bestAudioUrl ?? "", "https://high.m4a", "best url picks high")

        // With no high quality, picks medium
        let item2 = PlaylistItem(
            trackToken: "t2", artistName: "A", albumName: "B", songName: "C",
            songRating: 0, albumArtUrl: nil, additionalAudioUrl: nil,
            audioUrlMap: AudioUrlMap(
                highQuality: AudioUrl(bitrate: nil, encoding: nil, audioUrl: nil, protocol_: nil),
                mediumQuality: AudioUrl(bitrate: "128", encoding: "aac", audioUrl: "https://med.m4a", protocol_: "http"),
                lowQuality: nil
            ),
            songDetailUrl: nil, stationId: nil, songIdentity: nil, adToken: nil
        )
        TestRunner.assertEqual(item2.bestAudioUrl ?? "", "https://med.m4a", "best url falls to medium")
    }

    static func testPandoraResponseError() {
        let json = """
        {
            "stat": "fail",
            "message": "Invalid credentials",
            "code": 1002
        }
        """.data(using: .utf8)!

        do {
            let resp = try JSONDecoder().decode(PandoraResponse<UserLoginResult>.self, from: json)
            TestRunner.assert(!resp.isOk, "error response stat fail")
            TestRunner.assertEqual(resp.code ?? 0, 1002, "error code")
            TestRunner.assertEqual(resp.message ?? "", "Invalid credentials", "error message")
        } catch {
            TestRunner.assert(false, "error response decode: \(error)")
        }
    }

    static func testPlaylistItemAdDetection() {
        let ad = PlaylistItem(
            trackToken: nil, artistName: nil, albumName: nil, songName: nil,
            songRating: nil, albumArtUrl: nil, additionalAudioUrl: nil,
            audioUrlMap: nil, songDetailUrl: nil, stationId: nil, songIdentity: nil,
            adToken: "ad123"
        )
        TestRunner.assert(ad.isAd, "ad item detected")

        let song = PlaylistItem(
            trackToken: "t1", artistName: "A", albumName: "B", songName: "C",
            songRating: 0, albumArtUrl: nil, additionalAudioUrl: nil,
            audioUrlMap: nil, songDetailUrl: nil, stationId: nil, songIdentity: nil,
            adToken: nil
        )
        TestRunner.assert(!song.isAd, "song item not ad")
    }

    static func testLastStationSelection() {
        let json = """
        {
            "stat": "ok",
            "result": {
                "stations": [
                    { "stationId": "s1", "stationName": "First", "stationToken": "tok1" },
                    { "stationId": "s2", "stationName": "Second", "stationToken": "tok2" },
                    { "stationId": "s3", "stationName": "Third", "stationToken": "tok3" }
                ]
            }
        }
        """.data(using: .utf8)!

        let resp = try! JSONDecoder().decode(PandoraResponse<StationListResult>.self, from: json)
        let stations = resp.result!.stations

        // Saved token matches second station
        let match = stations.first(where: { $0.stationToken == "tok2" }) ?? stations.first
        TestRunner.assertEqual(match?.stationName ?? "", "Second", "last station: saved token matches")

        // No saved token — falls back to first
        let noMatch = stations.first(where: { $0.stationToken == "tokMissing" }) ?? stations.first
        TestRunner.assertEqual(noMatch?.stationName ?? "", "First", "last station: missing token falls back to first")

        // Nil saved token — falls back to first
        let nilToken: String? = nil
        let nilMatch = stations.first(where: { $0.stationToken == nilToken }) ?? stations.first
        TestRunner.assertEqual(nilMatch?.stationName ?? "", "First", "last station: nil token falls back to first")
    }
}
