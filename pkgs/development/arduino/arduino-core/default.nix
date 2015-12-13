{ stdenv, fetchFromGitHub, jdk, jre, ant, coreutils, gnugrep, file,
libusb, unzip, zlib, ncurses, readline
, withGui ? false, gtk2 ? null
}:

assert withGui -> gtk2 != null;

stdenv.mkDerivation rec {

  version = "1.6.5";
  name = "arduino${stdenv.lib.optionalString (withGui == false) "-core"}-${version}";

  src = fetchFromGitHub {
    owner = "arduino";
    repo = "Arduino";
    rev = "${version}";
    sha256 = "0qy1zizqshqzwppgbiphrr3mryypb8zky93jf72mac091b22jpn8";
  };

  buildInputs = [ jdk ant file libusb unzip zlib ncurses readline];

  buildPhase = ''
    cd ./build && ant
    cd ..
  '';

  installPhase = ''
    mkdir -p $out/share/arduino
    cp -r ./build/linux/work/* "$out/share/arduino/"
    echo ${version} > $out/share/arduino/lib/version.txt


    ${stdenv.lib.optionalString withGui ''

      mkdir -p "$out/bin"
      sed -i -e "s|^JAVA=java|JAVA=${jdk}/bin/java|" "$out/share/arduino/arduino"
      sed -i -e "s|^LD_LIBRARY_PATH=|LD_LIBRARY_PATH=${gtk2}/lib:|" "$out/share/arduino/arduino"
      ln -sr "$out/share/arduino/arduino" "$out/bin/arduino"
    ''}

    # Fixup "/lib64/ld-linux-x86-64.so.2" like references in ELF executables.
    echo "running patchelf on prebuilt binaries:"
    find "$out" | while read filepath; do
        if file "$filepath" | grep -q "ELF.*executable"; then
            # skip target firmware files
            if echo "$filepath" | grep -q "\.elf$"; then
                continue
            fi
            echo "setting interpreter $(cat "$NIX_CC"/nix-support/dynamic-linker) in $filepath"
            patchelf --set-interpreter "$(cat "$NIX_CC"/nix-support/dynamic-linker)" "$filepath"
            test $? -eq 0 || { echo "patchelf failed to process $filepath"; exit 1; }
            if readelf -d "$filepath" | grep "NEEDED" | grep "libz"; then
              echo "setting rpath for ${zlib}/lib in $filepath"
              patchelf --set-rpath ${zlib}/lib \
                "$filepath"
              test $? -eq 0 || { echo "patchelf failed to process $filepath"; exit 1; }
            fi
        fi
    done

    echo "Patch avrdude:"
    mkdir $out/lib/
    ln -s ${ncurses}/lib/libncursesw.so.5       $out/lib/libtinfo.so.5
    patchelf --set-rpath ${libusb}/lib:${readline}/lib:${ncurses}/lib:$out/lib \
        "$out/share/arduino/hardware/tools/avr/bin/avrdude_bin"

    echo "Patch astylej with ${stdenv.cc.cc}/lib"
    patchelf --set-rpath ${stdenv.cc.cc}/lib "$out/share/arduino/lib/libastylej.so"

  '';

  postFixup = ''
      ${stdenv.lib.optionalString withGui ''
      echo
      echo " ***** WARNING *****"
      echo " * Arduino IDE will copy jssc .so to your HOME after the first start and needs to be elf patched"
      echo " * the result is that Arduino can't find any serial ports"
      echo " * Please run:"
      echo "   patchelf --set-rpath ${stdenv.cc.cc}/lib ~/.jssc/linux/libjSSC-2.8_x86_64.so"
      echo " * OR"
      echo "   patchelf --set-rpath ${stdenv.cc.cc}/lib ~/.jssc/linux/libjSSC-2.8_x86.so"
      echo " * depending on your arhitecture after the first start."
      echo " *"
      echo " * Don't forget to add your user to the 'dialout' group so you can write to Arduino."
      echo " *******************"
      echo
    ''}
  '';

  meta = with stdenv.lib; {
    description = "Open-source electronics prototyping platform";
    homepage = http://arduino.cc/;
    license = stdenv.lib.licenses.gpl2;
    platforms = platforms.all;
    maintainers = with maintainers; [ antono robberer bjornfor ];
  };
}
