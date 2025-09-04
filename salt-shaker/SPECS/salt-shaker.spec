Name:           salt-shaker
Version:        @@VERSION@@
Release:        @@RELEASE@@%{?dist}
Summary:        Portable Salt-SSH wrapper
License:        Proprietary
URL:            https://github.com/To3Knee/Salt-Shaker
BuildArch:      noarch
Source0:        salt-shaker-@@VERSION@@.tar.gz

%description
Portable Salt-SSH configuration and wrapper scripts (“Salt Shaker”).
No package installs required on managed nodes. Password auth supported.

%prep
%setup -q -n salt-shaker

%build
# nothing

%install
mkdir -p %{buildroot}@@PREFIX@@
cp -a * %{buildroot}@@PREFIX@@/

%files
@@PREFIX@@

%changelog
* Thu Sep 04 2025 To3Knee - @@VERSION@@-@@RELEASE@@
- Build from portable source tree
