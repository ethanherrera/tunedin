import SwiftUI

struct CollaboratorMonogram: View {
  let member: ConcertCollaborator
  let size: CGFloat

  var body: some View {
    Text(String(member.displayName.prefix(1)).uppercased())
      .font(.system(size: size * 0.38, weight: .black, design: .rounded))
      .foregroundStyle(TunedInDesign.actionForeground)
      .frame(width: size, height: size)
      .background(TunedInDesign.accentTint, in: Circle())
  }
}

struct CommentMonogram: View {
  let comment: ConcertComment

  var body: some View {
    Text(String(comment.displayName.prefix(1)).uppercased())
      .font(.caption.weight(.black))
      .foregroundStyle(TunedInDesign.actionForeground)
      .frame(width: 32, height: 32)
      .background(TunedInDesign.accentTint, in: Circle())
  }
}
