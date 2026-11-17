// Download with Digby: hands the page (or a link) to Digby Video Downloader through its own
// digby-video:// address. Digby then reads the page and shows the choices; nothing downloads by itself.
// The extension keeps nothing and talks to nothing but the app on this Mac.

function send(url, tabId) {
  if (!url || !/^https?:\/\//i.test(url)) return;
  chrome.tabs.update(tabId, { url: "digby-video://download?url=" + encodeURIComponent(url) });
}

chrome.action.onClicked.addListener((tab) => send(tab.url, tab.id));

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: "page", title: "Download with Digby", contexts: ["page", "video", "audio", "image"] });
  chrome.contextMenus.create({ id: "link", title: "Download Link with Digby", contexts: ["link"] });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  send(info.menuItemId === "link" ? info.linkUrl : info.pageUrl, tab.id);
});
