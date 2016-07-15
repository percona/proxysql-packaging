# Don't try fancy stuff like debuginfo, which is useless on binary-only
# packages. Don't strip binary too
# Be sure buildpolicy set to do nothing
%define        __spec_install_post %{nil}
%define          debug_package %{nil}
%define        __os_install_post %{_dbpath}/brp-compress

Summary: A high-performance MySQL proxy
Name: proxysql
Version: 1.2.0
Release: 1.0.1
License: GPL+
Group: Development/Tools
SOURCE0 : %{name}-%{version}.tar.gz
URL: http://www.proxysql.com/

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root

%description
%{summary}

%prep
%setup -q

%build
sed -i -e 's/c++11/c++0x/' lib/Makefile
sed -i -e 's/c++11/c++0x/' src/Makefile
make clean
make -j 4 build_deps
make -j 4

%install
install -d %{buildroot}/%{_bindir}
install -d  %{buildroot}/%{_sysconfdir}
install -d  %{buildroot}/%{_sysconfdir}/init.d
install -m 0755 src/proxysql %{buildroot}/%{_bindir}
install -m 0600 etc/proxysql.cnf %{buildroot}/%{_sysconfdir}
install -m 0755 etc/init.d/proxysql %{buildroot}/%{_sysconfdir}/init.d
install -d %{buildroot}/var/lib/proxysql

%clean
rm -rf %{buildroot}

%post
mkdir /var/run/%{name}
chkconfig --add %{name}

%postun
rm -rf /var/run/%{name}
chkconfig --del %{name}

%files
%defattr(-,root,root,-)
%config(noreplace) %{_sysconfdir}/%{name}.cnf
%{_bindir}/*
%{_sysconfdir}/init.d/%{name}

%changelog
* Fri Jul 15 2016  Evgeniy Patlan <evgeniy.patlan@percona.com> 1.2.0-1.0.1
- First build of proxysql for Percona.
