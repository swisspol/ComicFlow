YUI({filter:"raw"}).use("uploader", function(Y) {
  if ((Y.Uploader.TYPE == "html5") && !Y.UA.ios) {
    var uploadDone = false;
    
    var uploader = new Y.Uploader({
      width: "250px",
      height: "35px",
      multipleFiles: true,
      uploadURL: "upload",
      selectButtonLabel: "Select Files&hellip;"
    });
    uploader.set("dragAndDropArea", "body");
    
    uploader.render("#selectFilesButtonContainer");
    
    uploader.after("fileselect", function (event) {
      var fileList = event.fileList;
      var fileTable = Y.one("#filenames tbody");
      
      if ((fileList.length > 0) && Y.one("#nofiles")) {
        Y.one("#nofiles").remove();
      }
      
      if (uploadDone) {
        uploadDone = false;
        fileTable.setHTML("");
      }
      
      Y.each(fileList, function (fileInstance) {
        fileTable.append("<tr id='" + fileInstance.get("id") + "_row" + "'>" +
        "<td class='name'>" + fileInstance.get("name") + "</td>" +
        "<td class='size'>" + Math.round(fileInstance.get("size") / (1024 * 1024) * 10) / 10 + " MB</td>" +
        "<td class='status'>n/a</td>");
      });
    });
    
    uploader.on("uploadstart", function (event) {
      uploader.set("enabled", false);
      Y.one("#uploadFilesButton").addClass("yui3-button-disabled");
      Y.one("#uploadFilesButton").detach("click");
    });
    
    uploader.on("uploadprogress", function (event) {
      var fileRow = Y.one("#" + event.file.get("id") + "_row");
      fileRow.one(".status").setHTML("Uploading&hellip; (" + event.percentLoaded + "%)");
    });
    
    uploader.on("uploadcomplete", function (event) {
      var fileRow = Y.one("#" + event.file.get("id") + "_row");
      fileRow.one(".status").setHTML(event.data);
    });
    
    uploader.on("uploaderror", function (event) {
      var fileRow = Y.one("#" + event.file.get("id") + "_row");
      fileRow.one(".status").setHTML("ERROR (" + event.status + ")");
    });
    
    uploader.on("alluploadscomplete", function (event) {
      uploader.set("enabled", true);
      uploader.set("fileList", []);
      Y.one("#uploadFilesButton").removeClass("yui3-button-disabled");
      
      Y.one("#uploadFilesButton").on("click", function () {
        if (!uploadDone && uploader.get("fileList").length > 0) {
          uploader.uploadAll();
        }
      });
      uploadDone = true;
    });
    
    Y.one ("#uploadFilesButton").on("click", function () {
      if (!uploadDone && uploader.get("fileList").length > 0) {
        uploader.uploadAll();
      }
    });
    
  } else {
    Y.one("#uploaderContainer").set("text", "To use the ComicFlow uploader, please use a modern browser that supports HTML5.");
    Y.one("#filelist").remove();
  }
});
