Name:           salt-shaker
Version:        3.12
Release:        1.el8
Summary:        Salt-Shaker portable Salt SSH (air-gapped)
License:        MIT
URL:            https://github.com/To3Knee/Salt-Shaker
BuildArch:      x86_64
Requires:       /bin/bash
Source0:        %{name}-%{version}.tar.gz

%description
Portable Salt SSH framework for air-gapped EL7/EL8/EL9. Includes vendor onedir(s), runtime config, and wrappers.

%prep
%setup -q

%build
# no-op

%install
rm -rf "%{buildroot}"
mkdir -p "%{buildroot}/sto/salt-shaker"
# Install under PREFIX/<project>
mkdir -p "%{buildroot}/sto/salt-shaker/salt-shaker"
cp -a . "%{buildroot}/sto/salt-shaker/salt-shaker/"

%files
%defattr(-,root,root,-)
/sto/salt-shaker/salt-shaker
%doc /sto/salt-shaker/salt-shaker/README-INSTALL.txt

%post
echo "Installed Salt-Shaker under /sto/salt-shaker/salt-shaker"
echo "Wrappers: /sto/salt-shaker/salt-shaker/bin/"
echo "Runtime:  /sto/salt-shaker/salt-shaker/runtime/"

%changelog
* Fri Oct 03 2025 T03KNEE <To3Knee@salt-shaker> - 3.12-1
- Initial package with pruned artifacts.
