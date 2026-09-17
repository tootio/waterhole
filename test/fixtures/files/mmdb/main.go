// Builds the tiny MMDB fixtures used by Waterhole's tests.
// Documentation ranges only (RFC 5737 / RFC 3849) -- no real addresses.
package main

import (
	"log"
	"net"
	"os"

	"github.com/maxmind/mmdbwriter"
	"github.com/maxmind/mmdbwriter/mmdbtype"
)

type entry struct {
	cidr string
	data mmdbtype.Map
}

func build(path, dbType string, entries []entry) {
	w, err := mmdbwriter.New(mmdbwriter.Options{
		DatabaseType: dbType,
		RecordSize:   24,
		IPVersion:              6,
		IncludeReservedNetworks: true,
	})
	if err != nil {
		log.Fatal(err)
	}
	for _, e := range entries {
		_, network, err := net.ParseCIDR(e.cidr)
		if err != nil {
			log.Fatal(err)
		}
		if err := w.Insert(network, e.data); err != nil {
			log.Fatal(err)
		}
	}
	f, err := os.Create(path)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	if _, err := w.WriteTo(f); err != nil {
		log.Fatal(err)
	}
}

func main() {
	build("origin-asn.mmdb", "GeoLite2-ASN", []entry{
		{"203.0.113.0/24", mmdbtype.Map{
			"autonomous_system_number":       mmdbtype.Uint32(64500),
			"autonomous_system_organization": mmdbtype.String("Example Hosting LLC"),
		}},
		{"198.51.100.0/24", mmdbtype.Map{
			"autonomous_system_number":       mmdbtype.Uint32(64501),
			"autonomous_system_organization": mmdbtype.String("Example Residential ISP"),
		}},
		{"2001:db8::/32", mmdbtype.Map{
			"autonomous_system_number":       mmdbtype.Uint32(64500),
			"autonomous_system_organization": mmdbtype.String("Example Hosting LLC"),
		}},
	})

	build("user-country.mmdb", "GeoLite2-Country", []entry{
		{"203.0.113.0/24", mmdbtype.Map{
			"country": mmdbtype.Map{"iso_code": mmdbtype.String("US")},
		}},
		{"198.51.100.0/24", mmdbtype.Map{
			"country": mmdbtype.Map{"iso_code": mmdbtype.String("DE")},
		}},
		{"2001:db8::/32", mmdbtype.Map{
			"country": mmdbtype.Map{"iso_code": mmdbtype.String("US")},
		}},
	})
	log.Println("wrote fixtures")
}
