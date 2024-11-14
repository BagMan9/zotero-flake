{
  inputs = {
    nixpkgs = {
      url = github:nixos/nixpkgs/nixos-unstable;
    };
    flake-utils = {
      url = github:numtide/flake-utils;
    };
    zotero-src = {
      url = "git+file:/home/asahimbp/Desktop/Mint/zotero-client";
      flake = false;
    };
    zotero-reader-src = {
      url = "git+https://github.com/zotero/reader.git?submodules=1";
      flake = false;
    };
    zotero-pdf-worker-src = {
      url = "git+https://github.com/zotero/pdf-worker.git?submodules=1";
      flake = false;
    };
    zotero-note-editor-src = {
      url = "github:zotero/note-editor";
      flake = false;
    };
    zotero-styles = {
      url = "github:zotero/bundled-styles";
      flake = false;
    };
    zotero-translators = {
      url = "github:zotero/translators";
      flake = false;
    };
  };
  outputs = inputs @ { self, nixpkgs, flake-utils, zotero-src, zotero-reader-src, zotero-pdf-worker-src, zotero-note-editor-src, zotero-styles, zotero-translators, ... }: flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};

      pdf_worker_revision = "<COMMITREVISION>";
      pdf_reader_revision = "<COMMITREVISION>";
      note_editor_revision = "<COMMITREVISION>";
      app_revision = "<COMMITREVISION>";
      app_short_revision = "<SHORTCOMMITREVISION>";
      app_branch_name = "main";

      patch_package_json = name: package: patch: pkgs.stdenv.mkDerivation {
        name = "patched_${name}_package_json";
        unpackPhase = ''
          cp ${package}/package.json .
          ${patch}
        '';
        installPhase = ''
          mkdir -p $out
          cp package.json $out/
        '';
      };
      
      yarn_deps = pkgs.mkYarnModules {
        pname = "zotero-yarn-deps";
        version = "master";
        packageJSON = "${zotero-src}/package.json";
        yarnLock = ./yarn.lock;
        yarnNix = ./yarn.nix;
      };
      
      patched_reader_package_json = patch_package_json "reader" zotero-reader-src ''
        sed -i '50 a "raw-loader": "^4.0.2",' package.json
      '';     
      
      reader_yarn_deps = pkgs.mkYarnModules rec {
        pname = "reader-yarn-deps";
        version = "master";
        packageJSON = "${patched_reader_package_json}/package.json";
        yarnLock = ./reader_yarn.lock;
        yarnNix = ./reader_yarn.nix;
        preBuild = ''
          mkdir -p "deps/${pname}"
          ln -s "${zotero-reader-src}/epubjs" "deps/${pname}/epubjs" 
        '';
      };    
      pdf_worker_yarn_deps = pkgs.mkYarnModules {
        pname = "pdf-worker-yarn-deps";
        version = "master";
        packageJSON = "${zotero-pdf-worker-src}/package.json";
        yarnLock = ./pdf-worker_yarn.lock;
        yarnNix = ./pdf-worker_yarn.nix;
      };    
      note_editor_yarn_deps = pkgs.mkYarnModules {
        pname = "note-editor-yarn-deps";
        version = "master";
        packageJSON = "${zotero-note-editor-src}/package.json";
        yarnLock = ./note-editor_yarn.lock;
        yarnNix = ./note-editor_yarn.nix;
      };    

      patched_pdfjs_package_json = patch_package_json "pdfjs" "${zotero-reader-src}/pdfjs/pdf.js" ''
        sed -i '10d' package.json
        sed -i '2 a "version": "0.0.1",' package.json
      '';
      pdfjs_yarn_deps = pkgs.mkYarnModules {
        pname = "pdf.js";
        version = "master";
        packageJSON = "${patched_pdfjs_package_json}/package.json";
        yarnLock = ./pdfjs_yarn.lock;
        yarnNix = ./pdfjs_yarn.nix;
      };

      link_deps = path: package: ''
        ln -s ${package}/node_modules ${path}/node_modules
        export PATH=${package}/node_modules/.bin:$PATH
      '';
      purity_patches =''
        sed -i 's/git rev-parse HEAD/echo "${app_revision}"/g' app/scripts/dir_build
        sed -i 's/hash=`git .* --short HEAD`/hash=`echo "${app_short_revision}"`/g' app/scripts/dir_build
        sed -i 's/git rev-parse HEAD/echo "${pdf_worker_revision}"/g' js-build/pdf-worker.js
        sed -i 's/git rev-parse HEAD/echo "${pdf_reader_revision}"/g' js-build/pdf-reader.js
        sed -i 's/git rev-parse HEAD/echo "${note_editor_revision}"/g' js-build/note-editor.js
        sed -i 's/_getGitBranchName\\(\\) \\{/_getGitBranchName() {return "${app_branch_name}"/g' chrome/content/scaffold/scaffold.js
      '';
      skip_npm_command_patches = ''
        sed -i 's/npm ci/echo "Skipped npm ci"/g' js-build/pdf-reader.js
        sed -i 's/npm ci/echo "Skipped npm ci"/g' js-build/pdf-worker.js
        sed -i 's/npm ci/echo "Skipped npm ci"/g' js-build/note-editor.js       
        sed -i 's/npm run build/echo "Skipped npm run build"/g' js-build/pdf-reader.js
        sed -i 's/npm run build/echo "Skipped npm run build"/g' js-build/pdf-worker.js
        sed -i 's/npm run build/echo "Skipped npm run build"/g' js-build/note-editor.js
      '';
      aarch64_patches = ''
        sed -i 's/# Uncomment to build 32-bit/# Build for aarch64/g' app/linux/mozconfig
        sed -i 's/#ac_add_options --target=i386/ac_add_options --target=aarch64/g' app/linux/mozconfig
        sed -i 's/linux-x86_64/linux-aarch64/g' app/scripts/build_and_run
        sed -i '47d;54d' app/scripts/build_and_run
        sed -i 's/x86_64/aarch64/g' app/build.sh
        sed -i 's/x86_64/aarch64/g' app/scripts/dir_build
        sed -i 's/x86_64/aarch64/g' app/scripts/add_omni_file
      '';
      misc_patches = ''
        sed -i '1d;s/colors.yellow//g' js-build/build.js
        sed -i 's/$(arch)/"${if system == "aarch64-linux" then "aarch64" else "x86_64"}"/g' app/scripts/dir_build
        sed -i 's/"$SCRIPT_DIR/bash "$SCRIPT_DIR/g' app/scripts/build_and_run
        sed -i 's/"$SCRIPT_DIR/bash "$SCRIPT_DIR/g' app/scripts/dir_build
      '';
      
      shared_build_inputs = with pkgs; [
        nodejs rsync yarn bash git
      ];
    in rec {
      formatter = pkgs.alejandra;
      packages = rec {
        zotero-reader = pkgs.stdenv.mkDerivation rec {
          name = "zotero-reader";
          src = "${zotero-reader-src}";

          nativeBuildInputs = shared_build_inputs ++ [ reader_yarn_deps pdfjs_yarn_deps ];
          
          patchPhase = ''
            sed -i 's/npx //g' pdfjs/build
            sed -i 's/npm ci/echo "Skipped npm ci in reader pdfjs build"/g' pdfjs/build
          '';
          
          buildPhase = ''
            set -x
            ${link_deps "." reader_yarn_deps}
            ${link_deps "./pdfjs/pdf.js" pdfjs_yarn_deps}
            npm run build
            mkdir -p $out
            cp -r . $out/
          '';
        };
        zotero-pdf-worker = pkgs.stdenv.mkDerivation rec {
          name = "zotero-pdf-worker";
          src = "${zotero-pdf-worker-src}";

          nativeBuildInputs = shared_build_inputs ++ [ pdf_worker_yarn_deps pdfjs_yarn_deps ];

          patchPhase = ''
            sed -i 's/npx //g' scripts/build-pdfjs
            sed -i 's/npm ci --force/echo "Skipped npm ci in build-pdfjs"/g' scripts/build-pdfjs
            sed -i 's/git rev-parse HEAD/echo "${pdf_worker_revision}"/g' scripts/upload
          '';

          buildPhase = ''
            set -x
            ${link_deps "." pdf_worker_yarn_deps}
            ls -alt
            ${link_deps "./pdf.js" pdfjs_yarn_deps}
            npm run build
            mkdir -p $out
            cp -r . $out/
          '';
        };
        zotero-note-editor = pkgs.stdenv.mkDerivation rec {
          name = "zotero-note-editor";
          src = "${zotero-note-editor-src}";

          nativeBuildInputs = shared_build_inputs ++ [ note_editor_yarn_deps ];

          patchPhase = ''
            sed -i 's/git rev-parse HEAD/echo "${note_editor_revision}"/g' scripts/upload
          '';

          buildPhase = ''
            set -x
            ${link_deps "." note_editor_yarn_deps}
            npm run build
            mkdir -p $out
            cp -r . $out/
          '';
        };
        zotero = pkgs.stdenv.mkDerivation rec {
          name = "zotero";

          src = "${zotero-src}/";

          nativeBuildInputs = shared_build_inputs ++ [ yarn_deps ];

          patchPhase = ''
            ${purity_patches}
            ${if system == "aarch64-linux" then aarch64_patches else ""}
            ${skip_npm_command_patches}
            ${misc_patches}
          '';

          buildPhase = ''
            set -x
            ln -s ${zotero-styles} ./styles
            ln -s ${zotero-translators} ./translators
            ln -s ${zotero-reader} ./reader
            ln -s ${zotero-pdf-worker} ./pdf-worker
            ln -s ${zotero-note-editor} ./note-editor
            ${link_deps "." yarn_deps}
            NODE_ENV="debug" NODE_PATH="./node_modules" bash ./app/scripts/build_and_run -r
            cp -r ./dist $out
          '';

        };
      };
    });
}
