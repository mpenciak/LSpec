import Std.Data.RBMap

-- TODO: Taken from YSL, find a replacement or document

namespace Std.RBMap

def zipD (m₁ : RBMap α β₁ cmp) (m₂ : RBMap α β₂ cmp) (b₂ : β₂) : RBMap α (β₁ × β₂) cmp :=
  m₁.foldl (init := default) fun acc a b₁ => acc.insert a (b₁, m₂.findD a b₂)

end Std.RBMap