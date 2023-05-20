(fn mask? [value mask]
  `(= (b-and ,value ,mask) ,mask))

{: mask?}
