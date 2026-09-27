# Glass lab baseline

Run: `20260927-035111`. Native iOS 27 (iPhone 17 Pro simulator) against Operator's Flutter glass.

| Status | Count |
|---|---|
| pass | 0 |
| fail | 96 |
| missing | 120 |
| reference | 12 |
| error | 0 |

| Scene | Case | Title | Status | Failing measures |
|---|---|---|---|---|
| alert.three | dark-stripes | Alert with three actions | missing | — |
| alert.three | dark-white | Alert with three actions | missing | — |
| alert.three | light-stripes | Alert with three actions | missing | — |
| alert.three | light-white | Alert with three actions | missing | — |
| alert.two | dark-stripes | Alert with two actions | missing | — |
| alert.two | dark-white | Alert with two actions | missing | — |
| alert.two | light-stripes | Alert with two actions | missing | — |
| alert.two | light-white | Alert with two actions | missing | — |
| apple.calendar.toolbar | dark-none | Calendar grouped toolbar and bottom bar | reference | — |
| apple.calendar.toolbar | light-none | Calendar grouped toolbar and bottom bar | reference | — |
| apple.maps.sheet | dark-none | Maps sheet dragged to full, then to its smallest detent | reference | — |
| apple.maps.sheet | light-none | Maps sheet dragged to full, then to its smallest detent | reference | — |
| apple.photos.scroll | dark-none | Photos grid scrolled under the tab bar | reference | — |
| apple.photos.scroll | light-none | Photos grid scrolled under the tab bar | reference | — |
| apple.photos.search | dark-none | Photos search tab | reference | — |
| apple.photos.search | light-none | Photos search tab | reference | — |
| apple.reminders.menu | dark-none | Reminders list menu | reference | — |
| apple.reminders.menu | light-none | Reminders list menu | reference | — |
| apple.settings.large | dark-none | Settings large title under the bar | reference | — |
| apple.settings.large | light-none | Settings large title under the bar | reference | — |
| button.press | dark-stripes | Glass and prominent button press | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| button.press | light-stripes | Glass and prominent button press | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| button.styles | dark-black | Glass button styles, sizes and shapes | fail | ready.mad, ready.luminance, ready.rim_rms |
| button.styles | dark-stripes | Glass button styles, sizes and shapes | fail | ready.mad, ready.luminance, ready.rim_rms |
| button.styles | dark-white | Glass button styles, sizes and shapes | fail | ready.mad, ready.luminance, ready.rim_rms |
| button.styles | light-black | Glass button styles, sizes and shapes | fail | ready.mad, ready.luminance, ready.rim_rms |
| button.styles | light-stripes | Glass button styles, sizes and shapes | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| button.styles | light-white | Glass button styles, sizes and shapes | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| confirm.source | dark-stripes | Confirmation dialog anchored to its button | missing | — |
| confirm.source | light-stripes | Confirmation dialog anchored to its button | missing | — |
| contextmenu.card | dark-stripes | Context menu on a card | missing | — |
| contextmenu.card | light-stripes | Context menu on a card | missing | — |
| datepicker.compact | dark-white | Compact date picker | missing | — |
| datepicker.compact | light-white | Compact date picker | missing | — |
| datepicker.inline | dark-white | Inline date picker | missing | — |
| datepicker.inline | light-white | Inline date picker | missing | — |
| datepicker.wheel | dark-white | Wheel date picker | missing | — |
| datepicker.wheel | light-white | Wheel date picker | missing | — |
| list.form | dark-none | Inset grouped form | missing | — |
| list.form | light-none | Inset grouped form | missing | — |
| material.clear | dark-photo | Clear glass with and without the dimming layer | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.clear | dark-white | Clear glass with and without the dimming layer | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.clear | light-photo | Clear glass with and without the dimming layer | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.clear | light-white | Clear glass with and without the dimming layer | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.content | dark-photo | Content layer materials | missing | — |
| material.content | light-photo | Content layer materials | missing | — |
| material.edge.automatic | dark-scroll | Automatic scroll edge effect under an inline bar | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.edge.automatic | light-scroll | Automatic scroll edge effect under an inline bar | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.edge.hard | dark-scroll | Hard scroll edge effect under an inline bar | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.edge.hard | light-scroll | Hard scroll edge effect under an inline bar | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.edge.soft | dark-scroll | Soft scroll edge effect under an inline bar | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.edge.soft | light-scroll | Soft scroll edge effect under an inline bar | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.flip | dark-scroll | Small and large glass over content that turns white then black | missing | — |
| material.flip | light-scroll | Small and large glass over content that turns white then black | missing | — |
| material.interactive | dark-photo | Interactive glass press and drag | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.interactive | dark-stripes | Interactive glass press and drag | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.interactive | light-photo | Interactive glass press and drag | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| material.interactive | light-stripes | Interactive glass press and drag | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| material.materialize | dark-photo | Glass materializes in and out | missing | — |
| material.materialize | dark-stripes | Glass materializes in and out | missing | — |
| material.materialize | light-photo | Glass materializes in and out | missing | — |
| material.materialize | light-stripes | Glass materializes in and out | missing | — |
| material.merge | dark-stripes | Two circles merge and split in a container | missing | — |
| material.merge | light-stripes | Two circles merge and split in a container | missing | — |
| material.morph | dark-photo | Button morphs into a badge stack | missing | — |
| material.morph | dark-stripes | Button morphs into a badge stack | missing | — |
| material.morph | light-photo | Button morphs into a badge stack | missing | — |
| material.morph | light-stripes | Button morphs into a badge stack | missing | — |
| material.regular | dark-black | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-black-increase-contrast | Regular glass at three sizes | fail | ready.rim_rms, settled.rim_rms |
| material.regular | dark-black-reduce-motion | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-black-reduce-transparency | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-photo | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-photo-increase-contrast | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-photo-reduce-motion | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-photo-reduce-transparency | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-stripes | Regular glass at three sizes | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| material.regular | dark-stripes-increase-contrast | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-stripes-reduce-motion | Regular glass at three sizes | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| material.regular | dark-stripes-reduce-transparency | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-text | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-text-increase-contrast | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-text-reduce-motion | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-text-reduce-transparency | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-white | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-white-increase-contrast | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-white-reduce-motion | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | dark-white-reduce-transparency | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | light-black | Regular glass at three sizes | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.regular | light-photo | Regular glass at three sizes | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| material.regular | light-stripes | Regular glass at three sizes | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| material.regular | light-text | Regular glass at three sizes | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| material.regular | light-white | Regular glass at three sizes | fail | ready.rim_rms, ready.bbox_pt, ready.centre_pt |
| material.shapes | dark-stripes | Capsule, fixed radius and concentric shapes | missing | — |
| material.shapes | light-stripes | Capsule, fixed radius and concentric shapes | missing | — |
| material.tinted | dark-black | Tinted glass and a prominent button | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.tinted | dark-stripes | Tinted glass and a prominent button | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.tinted | dark-white | Tinted glass and a prominent button | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| material.tinted | light-black | Tinted glass and a prominent button | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.tinted | light-stripes | Tinted glass and a prominent button | fail | ready.mad, ready.luminance, ready.rim_rms |
| material.tinted | light-white | Tinted glass and a prominent button | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| material.union | dark-stripes | Glass union of four items in two groups | missing | — |
| material.union | light-stripes | Glass union of four items in two groups | missing | — |
| menu.bar | dark-photo | Menu from a toolbar button | missing | — |
| menu.bar | dark-photo-increase-contrast | Menu from a toolbar button | missing | — |
| menu.bar | dark-photo-reduce-motion | Menu from a toolbar button | missing | — |
| menu.bar | dark-photo-reduce-transparency | Menu from a toolbar button | missing | — |
| menu.bar | dark-stripes | Menu from a toolbar button | missing | — |
| menu.bar | dark-stripes-increase-contrast | Menu from a toolbar button | missing | — |
| menu.bar | dark-stripes-reduce-motion | Menu from a toolbar button | missing | — |
| menu.bar | dark-stripes-reduce-transparency | Menu from a toolbar button | missing | — |
| menu.bar | light-photo | Menu from a toolbar button | missing | — |
| menu.bar | light-stripes | Menu from a toolbar button | missing | — |
| menu.pressdrag | dark-stripes | Press the menu button and drag onto an item | missing | — |
| menu.pressdrag | light-stripes | Press the menu button and drag onto an item | missing | — |
| menu.submenu | dark-stripes | Menu with a submenu | missing | — |
| menu.submenu | light-stripes | Menu with a submenu | missing | — |
| navbar.badge | dark-stripes | Badge on a bar button | missing | — |
| navbar.badge | light-stripes | Badge on a bar button | missing | — |
| navbar.groups | dark-stripes | Toolbar groups, spacer and prominent action | missing | — |
| navbar.groups | light-stripes | Toolbar groups, spacer and prominent action | missing | — |
| navbar.inline | dark-black | Inline title, back button and trailing group | fail | ready.mad, ready.luminance, ready.rim_rms |
| navbar.inline | dark-stripes | Inline title, back button and trailing group | fail | ready.mad, ready.luminance, ready.rim_rms |
| navbar.inline | dark-white | Inline title, back button and trailing group | fail | ready.mad, ready.luminance, ready.rim_rms |
| navbar.inline | light-black | Inline title, back button and trailing group | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| navbar.inline | light-stripes | Inline title, back button and trailing group | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| navbar.inline | light-white | Inline title, back button and trailing group | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| navbar.large | dark-scroll | Large title with subtitle scrolling under the bar | missing | — |
| navbar.large | light-scroll | Large title with subtitle scrolling under the bar | missing | — |
| navbar.minimize | dark-scroll | Navigation bar minimizes on scroll | missing | — |
| navbar.minimize | light-scroll | Navigation bar minimizes on scroll | missing | — |
| navbar.push | dark-stripes | Toolbar items across push and pop | missing | — |
| navbar.push | light-stripes | Toolbar items across push and pop | missing | — |
| pagecontrol | dark-photo | Page control with a platter | missing | — |
| pagecontrol | light-photo | Page control with a platter | missing | — |
| picker.menu | dark-white | Menu picker | missing | — |
| picker.menu | light-white | Menu picker | missing | — |
| popover.bar | dark-stripes | Popover from a bar button | missing | — |
| popover.bar | light-stripes | Popover from a bar button | missing | — |
| progress | dark-white | Progress views and a thumbless slider | missing | — |
| progress | light-white | Progress views and a thumbless slider | missing | — |
| push.zoom | dark-stripes | Push with a zoom transition from a card | missing | — |
| push.zoom | light-stripes | Push with a zoom transition from a card | missing | — |
| search.bottom | dark-photo | Bottom search field above the keyboard | missing | — |
| search.bottom | light-photo | Bottom search field above the keyboard | missing | — |
| search.minimized | dark-photo | Minimized search button | missing | — |
| search.minimized | light-photo | Minimized search button | missing | — |
| search.scopes | dark-white | Search scopes | missing | — |
| search.scopes | light-white | Search scopes | missing | — |
| segmented | dark-stripes | Segmented control tapped, then dragged | missing | — |
| segmented | dark-white | Segmented control tapped, then dragged | missing | — |
| segmented | light-stripes | Segmented control tapped, then dragged | missing | — |
| segmented | light-white | Segmented control tapped, then dragged | missing | — |
| sheet.crossfade | dark-stripes | Cross-fade sheet presentation | missing | — |
| sheet.crossfade | light-stripes | Cross-fade sheet presentation | missing | — |
| sheet.detents | dark-photo | Sheet moved between its detents | fail | ready.mad, ready.luminance, ready.rim_rms |
| sheet.detents | dark-photo-increase-contrast | Sheet moved between its detents | fail | ready.mad, ready.rim_rms, settled.mad |
| sheet.detents | dark-photo-reduce-motion | Sheet moved between its detents | fail | ready.mad, ready.luminance, ready.rim_rms |
| sheet.detents | dark-photo-reduce-transparency | Sheet moved between its detents | fail | ready.mad, ready.luminance, ready.rim_rms |
| sheet.detents | dark-stripes | Sheet moved between its detents | fail | ready.mad, ready.luminance, ready.rim_rms |
| sheet.detents | dark-stripes-increase-contrast | Sheet moved between its detents | fail | ready.mad, ready.luminance, ready.rim_rms |
| sheet.detents | dark-stripes-reduce-motion | Sheet moved between its detents | fail | ready.mad, ready.luminance, ready.rim_rms |
| sheet.detents | dark-stripes-reduce-transparency | Sheet moved between its detents | fail | ready.mad, ready.luminance, ready.rim_rms |
| sheet.detents | light-photo | Sheet moved between its detents | fail | ready.mad, ready.luminance, ready.rim_rms |
| sheet.detents | light-stripes | Sheet moved between its detents | fail | ready.mad, ready.luminance, ready.rim_rms |
| sheet.scroll | dark-stripes | Large sheet with scrolling content | missing | — |
| sheet.scroll | light-stripes | Large sheet with scrolling content | missing | — |
| sheet.zoom | dark-stripes | Sheet zooms out of a toolbar button | missing | — |
| sheet.zoom | light-stripes | Sheet zooms out of a toolbar button | missing | — |
| slider | dark-stripes | Slider flicked, then dragged slowly | missing | — |
| slider | dark-white | Slider flicked, then dragged slowly | missing | — |
| slider | light-stripes | Slider flicked, then dragged slowly | missing | — |
| slider | light-white | Slider flicked, then dragged slowly | missing | — |
| stepper | dark-white | Stepper | missing | — |
| stepper | light-white | Stepper | missing | — |
| swipe.row | dark-none | Swipe actions on a row | missing | — |
| swipe.row | light-none | Swipe actions on a row | missing | — |
| tabbar.accessory | dark-scroll | Tab bar bottom accessory, expanded then inline | missing | — |
| tabbar.accessory | light-scroll | Tab bar bottom accessory, expanded then inline | missing | — |
| tabbar.badge | dark-stripes | Tab badge | missing | — |
| tabbar.badge | light-stripes | Tab badge | missing | — |
| tabbar.drag | dark-stripes | Tab selection lens dragged across tabs | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.drag | dark-stripes-increase-contrast | Tab selection lens dragged across tabs | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.drag | dark-stripes-reduce-motion | Tab selection lens dragged across tabs | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.drag | dark-stripes-reduce-transparency | Tab selection lens dragged across tabs | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.drag | light-stripes | Tab selection lens dragged across tabs | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.minimize | dark-scroll | Tab bar minimizes on scroll | missing | — |
| tabbar.minimize | light-scroll | Tab bar minimizes on scroll | missing | — |
| tabbar.press | dark-stripes | Tab bar press and hold | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.press | light-stripes | Tab bar press and hold | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.prominent | dark-stripes | Prominent tab | missing | — |
| tabbar.prominent | light-stripes | Prominent tab | missing | — |
| tabbar.rest | dark-black | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-black-increase-contrast | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-black-reduce-motion | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-black-reduce-transparency | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-photo | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-photo-increase-contrast | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-photo-reduce-motion | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-photo-reduce-transparency | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-stripes | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-stripes-increase-contrast | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-stripes-reduce-motion | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-stripes-reduce-transparency | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-white | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-white-increase-contrast | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-white-reduce-motion | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | dark-white-reduce-transparency | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | light-black | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | light-photo | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | light-stripes | Tab bar with a search tab | fail | ready.mad, ready.luminance, ready.rim_rms |
| tabbar.rest | light-white | Tab bar with a search tab | fail | ready.mad, ready.rim_rms, ready.bbox_pt |
| tabbar.search | dark-photo | Search tab morphs into a field | missing | — |
| tabbar.search | light-photo | Search tab morphs into a field | missing | — |
| textfield | dark-black | Text and search fields | missing | — |
| textfield | dark-white | Text and search fields | missing | — |
| textfield | light-black | Text and search fields | missing | — |
| textfield | light-white | Text and search fields | missing | — |
| toggle | dark-black | Switch tapped, then its knob dragged | missing | — |
| toggle | dark-stripes | Switch tapped, then its knob dragged | missing | — |
| toggle | dark-white | Switch tapped, then its knob dragged | missing | — |
| toggle | light-black | Switch tapped, then its knob dragged | missing | — |
| toggle | light-stripes | Switch tapped, then its knob dragged | missing | — |
| toggle | light-white | Switch tapped, then its knob dragged | missing | — |
| toolbar.bottom | dark-photo | Bottom toolbar with groups | missing | — |
| toolbar.bottom | dark-stripes | Bottom toolbar with groups | missing | — |
| toolbar.bottom | light-photo | Bottom toolbar with groups | missing | — |
| toolbar.bottom | light-stripes | Bottom toolbar with groups | missing | — |
