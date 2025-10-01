#!/bin/bash
# Fix shebang paths in extracted binaries
# Save as: /sto/salt-shaker/scripts/fix-shebang.sh

PROJECT_ROOT="/sto/salt-shaker"
BUNDLED_PYTHON="python3.10"

echo "=== Fixing Salt Shaker Shebang Paths ==="
echo "Project Root: ${PROJECT_ROOT}"

for plat in el7 el8 el9; do
    plat_dir="${PROJECT_ROOT}/vendor/${plat}"
    echo ""
    echo "=== Fixing ${plat^^} Platform ==="
    
    if [ ! -d "${plat_dir}" ]; then
        echo "❌ Directory not found: ${plat_dir}"
        continue
    fi
    
    python_bin="${plat_dir}/bin/${BUNDLED_PYTHON}"
    if [ ! -x "${python_bin}" ]; then
        echo "⚠ Bundled Python not found: ${python_bin}"
        # Try alternative locations
        python_bin=$(find "${plat_dir}" -name "${BUNDLED_PYTHON}" -type f -executable 2>/dev/null | head -1)
        if [ -n "${python_bin}" ]; then
            echo "✓ Found Python at: ${python_bin}"
        else
            echo "❌ No bundled Python found"
            continue
        fi
    fi
    
    echo "🐍 Using Python: ${python_bin}"
    
    # Fix shebangs in all executable files
    fixed_count=0
    for binary in $(find "${plat_dir}" -type f -executable 2>/dev/null | grep -E "(salt|python)"); do
        if head -n1 "$binary" | grep -q "^#!/"; then
            original=$(head -n1 "$binary")
            # Fix common shebang issues
            if echo "$original" | grep -q "/usr/bin/env python\|/usr/bin/python\|/bin/python"; then
                if sed -i "1s|^#!.*python.*|\#!${python_bin}|" "$binary" 2>/dev/null; then
                    ((fixed_count++))
                    echo "✓ Fixed: $(basename "$binary")"
                fi
            elif echo "$original" | grep -q "bin/python"; then
                # Fix double bin/ paths
                if sed -i "1s|bin/bin/python|bin/python|" "$binary" 2>/dev/null; then
                    ((fixed_count++))
                    echo "✓ Fixed double bin: $(basename "$binary")"
                fi
            fi
        fi
    done
    
    echo "📊 Fixed ${fixed_count} shebangs in ${plat}"
done

echo ""
echo "=== Shebang Fix Complete ==="
echo "🔄 Re-run your test script now!"
