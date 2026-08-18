# Design references

Screenshots referenced by `docs/02-design-system.md` §7 and §9.

The directory is tracked with this file because §7 has named it as the storage
location since it was written, and it did not exist — so every reference in that
section pointed at nothing.

## Rules (§7)

- **Mobile screenshots only.** Web UI does not translate: different layout model,
  no hover, a fifth of the width. Converting a web design to Flutter produces a
  website squeezed into a phone.
- Name for **what the shot demonstrates**, not for the app it came from alone:
  `brilliant-card-density.png`, `gmaps-timeline-legs.png`,
  `cashapp-amount-hierarchy.png`.
- When citing one, say what to take: "the card density here", never "make it look
  like this".

## A note on the current reference set

Two of the references in use — Perplexity and Google Flights — were taken from
their **web** interfaces, which §7 forbids. Both ship mobile apps; screenshot
those instead. What they are cited for (the intake input, and constraint chips
sitting above results) is sound and unaffected.

The remainder are iOS-first. §9 already says what to take from an iOS reference
and what never to: take spacing, hierarchy and content patterns; leave the
navigation chrome, because Amora is Material 3.
