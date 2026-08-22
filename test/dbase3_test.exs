defmodule DBase3Test do
  use ExUnit.Case
  doctest DBF

  test "version (03) dBase III tables reject duplicate decoded field names" do
    assert {:error,
            %DBF.DatabaseError{
              reason: :invalid_schema,
              cause: :duplicate_field_name,
              context: %{field_name: "Point_ID"}
            }} = DBF.open("test/dbf_files/dbase_03.dbf")
  end

  describe "When reading version (83) dBase III with memo file" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_83.dbf")
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 0x83
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[2003-12-18]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 67
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "the first record is all that we wanted", context do
      record = %{
        "ACTIVE" => true,
        "AGRPCOUNT" => 0.0,
        "CATCOUNT" => 2.0,
        "CODE" => "1",
        "COST" => 0.0,
        "DESC" =>
          "Our Original assortment...a little taste of heaven for everyone.  Let us\r\nselect a special assortment of our chocolate and pastel favorites for you.\r\nEach petit four is its own special hand decorated creation. Multi-layers of\r\nmoist cake with combinations of specialty fillings create memorable cake\r\nconfections. Varietes include; Luscious Lemon, Strawberry Hearts, White\r\nChocolate, Mocha Bean, Roasted Almond, Triple Chocolate, Chocolate Hazelnut,\r\nGrand Orange, Plum Squares, Milk chocolate squares, and Raspberry Blanc.",
        "ID" => 87.0,
        "IMAGE" => "graphics/00000001/1.jpg",
        "NAME" => "Assorted Petits Fours",
        "ORDER" => 87.0,
        "PGRPCOUNT" => 0.0,
        "PRICE" => 0.0,
        "TAXABLE" => true,
        "THUMBNAIL" => "graphics/00000001/t_1.jpg",
        "WEIGHT" => 5.51
      }

      assert {:record, record} == DBF.get(context.db, 0)
    end

    test "record nine matches the independent DBF/DBT oracle", context do
      record = %{
        "ACTIVE" => true,
        "AGRPCOUNT" => 0.0,
        "CATCOUNT" => 1.0,
        "CODE" => "AB01",
        "COST" => 37.95,
        "DESC" =>
          "Once tasted you will understand why we won The\r\nBoston Herald's Fruitcake Taste-off. Judges liked its generous size,\r\nluscious appearance, moist texture and fruit to cake ratio ... commented one\r\njudge \"It's a lip Smacker!\" Our signature fruitcake is baked with carefully\r\nselected ingredients that will be savored until the last moist crumb is\r\ndevoured each golden slice is brimming with Australian glaced apricots,\r\ntoasted pecans, candied orange peel, and currants, folded gently into a\r\nbrandy butter batter and slowly baked to perfection and then generously\r\nimbibed with \"Holiday Spirits\". Presented in a gift tin.  (3lbs. 4oz)",
        "ID" => 34.0,
        "IMAGE" => "graphics/00000001/AB01.jpg",
        "NAME" => "Apricot Brandy Fruitcake",
        "ORDER" => 34.0,
        "PGRPCOUNT" => 0.0,
        "PRICE" => 37.95,
        "TAXABLE" => false,
        "THUMBNAIL" => "graphics/00000001/t_AB01.jpg",
        "WEIGHT" => 0.0
      }

      assert {:record, record} == DBF.get(context.db, 9)
    end

    test "the complete schema matches the independent summary", context do
      assert [
               {"ID", "N", 19, 0},
               {"CATCOUNT", "N", 19, 0},
               {"AGRPCOUNT", "N", 19, 0},
               {"PGRPCOUNT", "N", 19, 0},
               {"ORDER", "N", 19, 0},
               {"CODE", "C", 50, 0},
               {"NAME", "C", 100, 0},
               {"THUMBNAIL", "C", 254, 0},
               {"IMAGE", "C", 254, 0},
               {"PRICE", "N", 13, 2},
               {"COST", "N", 13, 2},
               {"DESC", "M", 10, 0},
               {"WEIGHT", "N", 13, 2},
               {"TAXABLE", "L", 1, 0},
               {"ACTIVE", "L", 1, 0}
             ] ==
               Enum.map(context.db.fields, &{&1.name, &1.type, &1.length, &1.decimal})
    end

    test "exact numerics preserve descriptor scale" do
      db = DBF.open!("test/dbf_files/dbase_83.dbf", numeric: :exact)
      on_exit(fn -> DBF.close(db) end)

      assert {:record, first} = DBF.get(db, 0)
      assert first["ID"] == 87
      assert Decimal.equal?(first["WEIGHT"], Decimal.new("5.51"))

      assert {:record, ninth} = DBF.get(db, 9)
      assert ninth["ID"] == 34
      assert Decimal.equal?(ninth["PRICE"], Decimal.new("37.95"))
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end
  end
end
