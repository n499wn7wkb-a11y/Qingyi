private func require(_ condition: @autoclosure () -> Bool, _ message: String = "check failed") {
    guard condition() else { fatalError(message) }
}
import Foundation
@main struct Check {
 static func main() {
  var state=GoogleResultStability()
  require(!state.observe(text:"译文",advanced:true,loading:false,loadingKnown:true,now:0))
  require(!state.observe(text:"译文",advanced:true,loading:false,loadingKnown:true,now:0.4))
  require(state.observe(text:"译文",advanced:true,loading:false,loadingKnown:true,now:0.61))
  var unknown=GoogleResultStability()
  require(!unknown.observe(text:"译文",advanced:true,loading:false,loadingKnown:false,now:0))
  require(!unknown.observe(text:"译文",advanced:true,loading:false,loadingKnown:false,now:1.9))
  require(unknown.observe(text:"译文",advanced:true,loading:false,loadingKnown:false,now:2.01))
  require(!state.observe(text:"新译文",advanced:true,loading:false,loadingKnown:true,now:5))
  require(!state.observe(text:"新译文",advanced:true,loading:true,loadingKnown:true,now:6))
  require(!state.observe(text:"新译文",advanced:true,loading:false,loadingKnown:true,now:7))
  require(!state.observe(text:"新译文",advanced:false,loading:false,loadingKnown:true,now:8))
  require(!state.observe(text:"",advanced:true,loading:false,loadingKnown:true,now:9))
  print("PASS: 0.6-second known-loading quiet period; 2-second unknown-page fallback; reset on changed output, loading, wrong mode or empty text")
 }
}
