(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.BetterCallBlissRecentPagination = factory();
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';
  function create(size) {
    var items = [], index = 0;
    function page() {
      var pages = Math.max(1, Math.ceil(items.length / size));
      index = Math.max(0, Math.min(index, pages - 1));
      return { index: index, pages: pages, items: items.slice(index * size, (index + 1) * size) };
    }
    return {
      update: function (next) {
        var anchor = index > 0 && items[index * size] && items[index * size].id;
        items = next.slice();
        if (anchor) {
          var found = items.findIndex(function (item) { return item.id === anchor; });
          if (found >= 0) index = Math.floor(found / size);
        }
        return page();
      },
      move: function (delta) { index += delta; return page(); }
    };
  }
  return { create: create };
}));
