(function() {
  "use strict";

  var UPLOAD_URL = "/images/upload";
  var ACCEPTED_TYPES = /^(image\/|video\/|audio\/)/;

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute("content") : "";
  }

  function getTextarea() {
    return document.getElementById("post_content");
  }

  function insertAtCursor(textarea, text) {
    var start = textarea.selectionStart;
    var end = textarea.selectionEnd;
    var before = textarea.value.substring(0, start);
    var after = textarea.value.substring(end);
    textarea.value = before + text + after;
    textarea.selectionStart = textarea.selectionEnd = start + text.length;
    textarea.focus();
    if (typeof doRender === "function") doRender();
  }

  function setUploading(active) {
    var indicator = document.getElementById("upload-indicator");
    var uploadBtn = document.getElementById("upload-btn");
    if (indicator) indicator.style.display = active ? "inline-flex" : "none";
    if (uploadBtn) uploadBtn.disabled = active;
  }

  function uploadFile(file) {
    if (!ACCEPTED_TYPES.test(file.type)) {
      alert("Unsupported file type: " + file.type);
      return;
    }

    setUploading(true);
    var formData = new FormData();
    formData.append("file", file);

    var xhr = new XMLHttpRequest();
    xhr.open("POST", UPLOAD_URL, true);
    xhr.setRequestHeader("X-CSRF-Token", csrfToken());
    xhr.setRequestHeader("Accept", "application/json");

    var progressBar = document.getElementById("upload-progress");
    if (progressBar) {
      progressBar.style.display = "block";
      xhr.upload.onprogress = function(e) {
        if (e.lengthComputable) {
          progressBar.value = (e.loaded / e.total) * 100;
        }
      };
    }

    xhr.onload = function() {
      setUploading(false);
      if (progressBar) {
        progressBar.style.display = "none";
        progressBar.value = 0;
      }

      if (xhr.status === 201) {
        var data = JSON.parse(xhr.responseText);
        var textarea = getTextarea();
        if (textarea && data.tag) {
          insertAtCursor(textarea, data.tag);
        }
      } else {
        var msg = "Upload failed";
        try { msg = JSON.parse(xhr.responseText).error || msg; } catch(e) {}
        alert(msg);
      }
    };

    xhr.onerror = function() {
      setUploading(false);
      if (progressBar) progressBar.style.display = "none";
      alert("Upload failed: network error");
    };

    xhr.send(formData);
  }

  function handleFiles(files) {
    for (var i = 0; i < files.length; i++) {
      uploadFile(files[i]);
    }
  }

  document.addEventListener("DOMContentLoaded", function() {
    var textarea = getTextarea();
    if (!textarea) return;

    // AJAX upload button
    var uploadBtn = document.getElementById("upload-btn");
    var fileInput = document.getElementById("upload-file-input");

    if (uploadBtn && fileInput) {
      uploadBtn.addEventListener("click", function(e) {
        e.preventDefault();
        if (fileInput.files.length > 0) {
          handleFiles(fileInput.files);
          fileInput.value = "";
        } else {
          fileInput.click();
        }
      });

      fileInput.addEventListener("change", function() {
        if (fileInput.files.length > 0) {
          handleFiles(fileInput.files);
          fileInput.value = "";
        }
      });
    }

    // Drag and drop on textarea
    var dropZone = document.getElementById("drop-zone") || textarea;

    dropZone.addEventListener("dragover", function(e) {
      e.preventDefault();
      e.stopPropagation();
      dropZone.classList.add("drop-active");
    });

    dropZone.addEventListener("dragleave", function(e) {
      e.preventDefault();
      e.stopPropagation();
      dropZone.classList.remove("drop-active");
    });

    dropZone.addEventListener("drop", function(e) {
      e.preventDefault();
      e.stopPropagation();
      dropZone.classList.remove("drop-active");
      if (e.dataTransfer.files.length > 0) {
        handleFiles(e.dataTransfer.files);
      }
    });

    // Paste image from clipboard
    textarea.addEventListener("paste", function(e) {
      var items = e.clipboardData && e.clipboardData.items;
      if (!items) return;

      for (var i = 0; i < items.length; i++) {
        if (ACCEPTED_TYPES.test(items[i].type)) {
          e.preventDefault();
          var file = items[i].getAsFile();
          if (file) uploadFile(file);
          return;
        }
      }
    });

  });
})();
