// Override the DS Icon so glyphs always resolve from local icon-data.
(function () {
  var ns = (window.WantedDesignSystem_f8da76 = window.WantedDesignSystem_f8da76 || {});
  function Icon(props) {
    var name = props.name, size = props.size || 24;
    var rest = {};
    for (var k in props) { if (k !== "name" && k !== "size") rest[k] = props[k]; }
    var d = window.RC_ICONS && window.RC_ICONS[name];
    if (!d) return null;
    return React.createElement("svg", Object.assign({
      width: size, height: size, "aria-hidden": "true", viewBox: d.viewBox, fill: "none",
      dangerouslySetInnerHTML: { __html: d.body },
    }, rest));
  }
  ns.Icon = Icon;
})();
