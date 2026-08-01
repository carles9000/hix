document$.subscribe(function () {
  document.querySelectorAll(".md-nav__toggle").forEach(function (toggle) {
    toggle.addEventListener("change", function () {
      if (!this.checked) return;
      var item = this.closest(".md-nav__item--nested");
      if (!item) return;
      var siblings = item.parentElement.querySelectorAll(
        ":scope > .md-nav__item--nested > .md-nav__toggle"
      );
      siblings.forEach(function (t) {
        if (t !== toggle) t.checked = false;
      });
    });
  });
});
