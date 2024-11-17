{
  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    zotero-src = {
      url = "git+https://github.com/zotero/zotero.git";
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
    zotero-csl-locale = {
      url = "github:citation-style-language/locales";
      flake = false;
    };
    zotero-schema = {
      url = "github:zotero/zotero-schema";
      flake = false;
    };
    zotero-resource-SingleFile = {
      url = "github:gildas-lormeau/SingleFile";
      flake = false;
    };
    zotero-utilities = {
      url = "github:zotero/utilities";
      flake = false;
    };
    zotero-translate = {
      url = "github:zotero/translate";
      flake = false;
    };
    zotero-libreoffice-integration = {
      url = "github:zotero/zotero-libreoffice-integration";
      flake = false;
    };
    chai = {
      url = "github:chaijs/chai";
      flake = false;
    };
    mocha = {
      url = "github:mochajs/mocha";
      flake = false;
    };
    chai-as-promised = {
      url = "github:domenic/chai-as-promised";
      flake = false;
    };
    nixpkgs-old = {
      url = "github:NixOS/nixpkgs/b69de56fac8c2b6f8fd27f2eca01dcda8e0a4221";
    };
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-old,
    flake-utils,
    zotero-src,
    zotero-reader-src,
    zotero-pdf-worker-src,
    zotero-note-editor-src,
    zotero-styles,
    zotero-translators,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      pdf_worker_revision = zotero-pdf-worker-src.rev;
      pdf_reader_revision = zotero-pdf-worker-src.rev;
      note_editor_revision = zotero-note-editor-src.rev;
      app_revision = zotero-src.rev;
      app_short_revision = zotero-src.shortRev;
      app_branch_name = "main";

      patch_package_json = name: path: patch:
        pkgs.stdenv.mkDerivation {
          name = "patched_${name}_package_json";
          src = builtins.path {
            name = "${name}_package_json";
            inherit path;
            filter = filepath: type: type == "regular" && baseNameOf filepath == "package.json" && dirOf filepath == "${path}";
          };
          buildPhase = ''
            ${patch}
          '';
          installPhase = ''
            mkdir -p $out
            cp package.json $out/
          '';
        };

      patched_zotero_package_json =
        patch_package_json "zotero" zotero-src ''
        '';

      yarn_deps = pkgs.mkYarnModules {
        pname = "zotero-yarn-deps";
        version = "master";
        packageJSON = "${patched_zotero_package_json}/package.json";
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
      purity_patches = ''
        # Git calls
        sed -i 's/git rev-parse HEAD/echo "${app_revision}"/g' app/scripts/dir_build
        sed -i 's/hash=`git .* --short HEAD`/hash=`echo "${app_short_revision}"`/g' app/scripts/dir_build
        sed -i 's/git rev-parse HEAD/echo "${pdf_worker_revision}"/g' js-build/pdf-worker.js
        sed -i 's/git rev-parse HEAD/echo "${pdf_reader_revision}"/g' js-build/pdf-reader.js
        sed -i 's/git rev-parse HEAD/echo "${note_editor_revision}"/g' js-build/note-editor.js
        sed -i 's/_getGitBranchName\\(\\) \\{/_getGitBranchName() {return "${app_branch_name}"/g' chrome/content/scaffold/scaffold.js

        # Firefox download
        sed -i 's/curl -O .*/echo "Skipped curl"/g' app/scripts/fetch_xulrunner
        sed -i 's/tar xvf .*/echo "Skipped tar xvf"/g' app/scripts/fetch_xulrunner
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
        sed -i 's/x86_64/aarch64/g' app/scripts/fetch_xulrunner
      '';
      shebang_patches = ''
        find ./app -type f -exec sed -i 's/\/bin\/bash/${lib.strings.escape ["/"] "${pkgs.bash}/bin/bash"}/g' {} \;
        find ./app -type f -exec sed -i 's/\/usr\/bin\/env python3/${lib.strings.escape ["/"] "${pkgs.python3}/bin/python"}/g' {} \;
      '';
      misc_patches = ''
        sed -i '1d;s/colors.yellow//g' js-build/build.js
        sed -i 's/$(arch)/"${
          if system == "aarch64-linux"
          then "aarch64"
          else "x86_64"
        }"/g' app/scripts/dir_build

        sed -i 's/replace_line .*{. /echo /g' app/scripts/fetch_xulrunner
        sed -i 's/rm "firefox-.*//g' app/scripts/fetch_xulrunner

        # Don't let the script take a hash of firefox for whatever reason
        # Plus I don't want to add openssl as a dependency
        sed -i 's/set -euo pipefail/exit 0/g' app/scripts/xulrunner_hash

        sed -i 's/.*LightweightThemeConsumer.*//g' app/build.sh
        sed -i 's/rm -rf "$omni_dir"//g' app/build.sh
        sed -i 's/rm -rf $BUILD_DIR/echo "Skipped rm -rf BUILD_DIR"/g' app/build.sh
        sed -i 's/rm -rf $build_dir/echo "Skipped rm -rf build_dir"/g' app/scripts/dir_build
        sed -i 's/cp.*removed-files.*$arch.*//g' app/build.sh

        # Don't enable update machinery
        sed -i 's/check_lfs_file.*updater.tar.xz"//g' app/build.sh
        sed -i 's/tar xf.*updater"//g' app/build.sh
        sed -i 's/chmod 755.*updater"//g' app/build.sh

        sed -i 's/"$APP_ROOT_DIR.*-purgecaches.*//g' app/scripts/build_and_run

        sed -i 's/# Copy icons/mkdir -p "$APPDIR\/icons"/g' app/build.sh
      '';

      shared_build_inputs = with pkgs; [
        nodejs
        rsync
        yarn
        bash
        git
      ];
    in rec {
      formatter = pkgs.alejandra;
      packages = rec {
        zotero-reader = pkgs.stdenv.mkDerivation rec {
          name = "zotero-reader";
          src = "${zotero-reader-src}";

          nativeBuildInputs = shared_build_inputs ++ [reader_yarn_deps pdfjs_yarn_deps];

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

          nativeBuildInputs = shared_build_inputs ++ [pdf_worker_yarn_deps pdfjs_yarn_deps];

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

          nativeBuildInputs = shared_build_inputs ++ [note_editor_yarn_deps];

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

        zotero-firefox = nixpkgs-old.legacyPackages.${system}.firefox-esr-115;
        
        zotero = pkgs.stdenv.mkDerivation rec {
          pname = "zotero";
          version = "master";

          src = "${zotero-src}/";

          nativeBuildInputs = with pkgs;
            [
              python3
              perl
              zip
              unzip
              yarn_deps
              zotero-firefox
              makeWrapper
              removeReferencesTo
            ]
            ++ shared_build_inputs;

          desktopItem = pkgs.makeDesktopItem {
            name = "zotero";
            exec = "zotero -url %U";
            icon = "zotero";
            comment = meta.description;
            desktopName = "Zotero";
            genericName = "Reference Management";
            categories = ["Office" "Database"];
            startupNotify = true;
            mimeTypes = ["x-scheme-handler/zotero" "text/plain"];
          };

          patchPhase = ''
            ${purity_patches}
            ${
              if system == "aarch64-linux"
              then aarch64_patches
              else ""
            }
            ${skip_npm_command_patches}
            ${shebang_patches}
            ${misc_patches}
          '';

          buildPhase = let
            fill_submodule = source: target_path: ''
              rm -rf ${target_path}
              mkdir -p ${dirOf target_path}
              cp -r --no-preserve=mode,ownership ${source} ${target_path}
            '';
          in ''
            # Show all commands
            set -x

            ${fill_submodule zotero-styles "./styles"}
            ${fill_submodule zotero-translators "./translators"}
            ${fill_submodule inputs.zotero-csl-locale "./chrome/content/zotero/locale/csl"}
            ${fill_submodule inputs.zotero-schema "./resource/schema/global"}
            ${fill_submodule inputs.zotero-resource-SingleFile "./resource/SingleFile"}
            ${fill_submodule inputs.zotero-utilities "./chrome/content/zotero/xpcom/utilities"}
            ${fill_submodule inputs.zotero-translate "./chrome/content/zotero/xpcom/translate"}
            ${fill_submodule inputs.zotero-libreoffice-integration "./app/modules/zotero-libreoffice-integration"}

            # Place the un-tarred Firefox download for app/scripts/fetch_xulrunner to deal with
            mkdir -p ./app/xulrunner
            cp -r -L --no-preserve=mode,ownership ${zotero-firefox}/lib/firefox ./app/xulrunner

            # Link these submodules; their content does not need to be modified
            ${fill_submodule zotero-reader "./reader"}
            ${fill_submodule zotero-pdf-worker "./pdf-worker"}
            ${fill_submodule zotero-note-editor "./note-editor"}

            ${link_deps "." yarn_deps}

            cp -r chrome/skin/default/zotero/16/light chrome/skin/default/zotero/16/white

            NODE_PATH="./node_modules" ./app/scripts/build_and_run -r

            mv app/staging/Zotero* app/staging/zotero

          '';

          installPhase = ''
            runHook preInstall

            mkdir -p "$prefix/lib"
            cp -r --preserve=mode app/staging/zotero "$prefix/lib"
            chmod +x "$prefix/lib/zotero/zotero"
            chmod +x "$prefix/lib/zotero/zotero-bin"
            chmod +x "$prefix/lib/zotero/glxtest"
            chmod +x "$prefix/lib/zotero/vaapitest"
            mkdir -p "$out/bin"

            # Use logic from https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/applications/networking/browsers/firefox/wrapper.nix

            makeWrapper "$prefix/lib/zotero/zotero" \
              "$out/bin/zotero" \
                --set MOZ_APP_LAUNCHER "zotero" \
                --set MOZ_LEGACY_PROFILES 1 \
                --set MOZ_ALLOW_DOWNGRADE 1 \
                --suffix PATH ':' "$out/bin" \
                --prefix XDG_DATA_DIRS : "$GSETTINGS_SCHEMAS_PATH" \
                --suffix XDG_DATA_DIRS : '${pkgs.adwaita-icon-theme}/share' \
                --set-default MOZ_ENABLE_WAYLAND 1 \
                "''${oldWrapperArgs[@]}"

            # Install desktop file and icons.
            mkdir -p $out/share/applications
            cp ${desktopItem}/share/applications/* $out/share/applications/
            ls app/staging/zotero
            for size in 32 64 128; do
              install -Dm444 app/staging/zotero/icons/icon$size.png \
                $out/share/icons/hicolor/''${size}x''${size}/apps/zotero.png
            done
            install -Dm444 app/staging/zotero/icons/symbolic.svg \
                $out/share/icons/hicolor/symbolic/apps/zotero-symbolic.svg


            runHook postInstall
          '';

          meta = with lib; {
            homepage = "https://www.zotero.org";
            description = "Collect, organize, cite, and share your research sources";
            mainProgram = "zotero";
            license = licenses.agpl3Only;
            platforms = ["x86_64-linux" "aarch64-linux"];
          };
        };
      };
    });
}
